import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/error_log.dart';
import 'pcm.dart';
import 'stem_model.dart';
import 'stem_separation.dart';

/// Stand von „Spuren trennen“.
enum StemPhase { idle, downloading, decoding, separating, failed }

/// Trennt Aufnahmen in Schlagzeug, Bass, Instrumente und Gesang (zum
/// Mischen und für besser klingendes Transponieren). Eine Aufgabe
/// gleichzeitig, app-weit; sie läuft weiter, auch wenn die Notenansicht
/// geschlossen wird.
///
/// Ablage: `<ApplicationSupport>/stems/<Aufnahme ohne Endung>/drums.wav`,
/// `bass.wav`, `other.wav`, `vocals.wav`, nur auf diesem Gerät (nicht abgeglichen, jedes Gerät rechnet
/// selbst). Die Aufnahme-Dateien heissen nach einer ID und ändern sich nie,
/// deshalb passt eine Ablage immer genau zu einer Aufnahme.
class StemService extends ChangeNotifier {
  StemService._();
  static final instance = StemService._();

  StemPhase phase = StemPhase.idle;

  /// Fortschritt der laufenden Phase (0..1).
  double progress = 0;

  /// Aufnahme, an der gerade gearbeitet wird.
  String? audioPath;

  /// Fehler der letzten Aufgabe (zum Anzeigen).
  String? error;

  bool get busy => phase == StemPhase.downloading || phase == StemPhase.decoding || phase == StemPhase.separating;

  /// Wird gerade die Aufnahme [path] bearbeitet?
  bool busyWith(String? path) => busy && path != null && path == audioPath;

  /// Wenn [stemsChanged] feuert, gibt es zu dieser Aufnahme neue Spuren.
  final stemsChanged = ValueNotifier<String?>(null);

  String? _support;
  bool _cancel = false;
  SendPort? _workerControl;

  Future<String> _supportDir() async => _support ??= (await getApplicationSupportDirectory()).path;

  static String _dirFor(String support, String audio) => p.join(support, 'stems', p.basenameWithoutExtension(audio));

  /// Fertige Spuren der Aufnahme [audio], oder null.
  /// In der Reihenfolge von [Stem].
  Future<List<String>?> stemsFor(String audio) async {
    final dir = _dirFor(await _supportDir(), audio);
    final files = [for (final st in Stem.values) p.join(dir, '${st.name}.wav')];
    for (final f in files) {
      if (!await File(f).exists()) return null;
    }
    return files;
  }

  /// Ordner der Spuren einer Aufnahme (für die gespeicherte Mischung).
  Future<String> folderFor(String audio) async => _dirFor(await _supportDir(), audio);

  /// Ist die Modell-Datei schon da?
  Future<bool> modelInstalled() async => StemModelFile.installed(await _supportDir());

  /// Spuren der Aufnahme [audio] löschen.
  Future<void> deleteStems(String audio) async {
    final dir = Directory(_dirFor(await _supportDir(), audio));
    if (await dir.exists()) await dir.delete(recursive: true);
    stemsChanged.value = null;
    stemsChanged.value = audio;
  }

  /// Spuren von Aufnahmen wegräumen, die es nicht mehr gibt (gelöscht oder
  /// ersetzt). [audioDir] ist der Aufnahme-Ordner der Bibliothek.
  Future<void> prune(String audioDir) async {
    try {
      final stems = Directory(p.join(await _supportDir(), 'stems'));
      if (!await stems.exists()) return;
      final names = <String>{};
      if (await Directory(audioDir).exists()) {
        await for (final f in Directory(audioDir).list()) {
          names.add(p.basenameWithoutExtension(f.path));
        }
      }
      await for (final d in stems.list()) {
        final name = p.basename(d.path);
        final working = busy && audioPath != null && p.basenameWithoutExtension(audioPath!) == name;
        if (d is Directory && !names.contains(name) && !working) {
          await d.delete(recursive: true);
        }
      }
    } catch (_) {}
  }

  /// Aufgabe abbrechen (wirkt nach dem laufenden Stück).
  void cancel() {
    if (!busy) return;
    _cancel = true;
    _workerControl?.send('cancel');
  }

  void _set(StemPhase ph, [double pr = 0]) {
    phase = ph;
    progress = pr;
    notifyListeners();
  }

  /// Trennt die Aufnahme [audio]. Lädt vorher (falls nötig) die Modell-Datei
  /// herunter. Gibt true zurück, wenn die Spuren danach da sind.
  Future<bool> separate(String audio) async {
    if (busy) return false;
    _cancel = false;
    error = null;
    audioPath = audio;
    final support = await _supportDir();
    final tmp = (await getTemporaryDirectory()).path;
    final raw = p.join(tmp, 'volti-stems-${p.basenameWithoutExtension(audio)}.f32');
    try {
      if (!StemModelFile.installed(support)) {
        _set(StemPhase.downloading);
        final ok = await StemModelFile.download(
          support,
          progress: (v) {
            progress = v;
            notifyListeners();
          },
          cancelled: () => _cancel,
        );
        if (!ok) return _finish();
      }
      if (_cancel) return _finish();

      _set(StemPhase.decoding);
      // Windows wandelt im Hintergrund-Isolate um (blockiert sonst), die
      // anderen hier (Android über einen eigenen Thread).
      RawAudio? decoded;
      if (!Platform.isWindows) decoded = await decodeAudio(audio, raw);
      if (_cancel) return _finish();

      final out = _dirFor(support, audio);
      // Frisch anfangen (Reste eines früheren Versuchs weg).
      if (await Directory(out).exists()) await Directory(out).delete(recursive: true);
      await Directory(out).create(recursive: true);
      final result = await _runWorker(
        StemWorkerJob(
          audio: audio,
          raw: raw,
          rate: decoded?.sampleRate,
          channels: decoded?.channels,
          model: StemModelFile.pathIn(support),
          outDir: out,
        ),
      );
      if (result == 'ok') {
        stemsChanged.value = null;
        stemsChanged.value = audio;
        return _finish(ok: true);
      }
      if (result == 'cancelled') return _finish();
      throw Exception(result);
    } catch (e, st) {
      error = e.toString();
      ErrorLog.record(e, st, where: 'Spuren trennen');
      _set(StemPhase.failed);
      return false;
    } finally {
      try {
        await File(raw).delete();
      } catch (_) {}
    }
  }

  bool _finish({bool ok = false}) {
    _workerControl = null;
    _set(StemPhase.idle);
    return ok;
  }

  Future<String> _runWorker(StemWorkerJob job) async {
    final events = ReceivePort();
    final done = Completer<String>();
    final iso = await Isolate.spawn(
      stemWorker,
      (job, events.sendPort),
      onError: events.sendPort,
      onExit: events.sendPort,
    );
    events.listen((m) {
      if (m is SendPort) {
        _workerControl = m;
        if (_cancel) m.send('cancel');
      } else if (m is List && m.length == 2 && m[0] is String && m[1] is num) {
        _set(m[0] == 'decode' ? StemPhase.decoding : StemPhase.separating, (m[1] as num).toDouble());
      } else if (m is String) {
        if (!done.isCompleted) done.complete(m);
      } else if (m is List) {
        // Fehler im Isolate: [Meldung, Ablauf]
        if (!done.isCompleted) done.complete('${m.first}');
      } else if (m == null) {
        // Isolate beendet
        if (!done.isCompleted) done.complete('Abbruch ohne Ergebnis');
      }
    });
    try {
      return await done.future;
    } finally {
      events.close();
      iso.kill();
    }
  }
}

@visibleForTesting
class StemWorkerJob {
  const StemWorkerJob({
    required this.audio,
    required this.raw,
    required this.rate,
    required this.channels,
    required this.model,
    required this.outDir,
  });
  final String audio, raw, model, outDir;
  final int? rate, channels;
}

/// Hintergrund-Isolate: umwandeln (Windows), zerlegen, WAV schreiben.
@visibleForTesting
Future<void> stemWorker((StemWorkerJob, SendPort) args) async {
  final (job, out) = args;
  final control = ReceivePort();
  out.send(control.sendPort);
  var cancelled = false;
  control.listen((m) {
    if (m == 'cancel') cancelled = true;
  });
  final writers = <WavWriter>[];
  StemModelRunner? runner;
  try {
    out.send(['decode', 0.0]);
    final raw = job.rate == null ? decodeAudioWindows(job.audio, job.raw) : RawAudio(job.raw, job.rate!, job.channels!);
    await Future<void>.delayed(Duration.zero);
    if (cancelled) return out.send('cancelled');
    final (left, right) = readStereo(raw);
    try {
      File(job.raw).deleteSync();
    } catch (_) {}
    out.send(['separate', 0.0]);
    runner = StemModelRunner(job.model);
    for (final st in Stem.values) {
      writers.add(WavWriter(p.join(job.outDir, '${st.name}.wav.part')));
    }
    final ok = await StemSeparation(run: runner.run).separate(
      left,
      right,
      (ch) {
        for (var st = 0; st < writers.length; st++) {
          writers[st].add(ch[2 * st], ch[2 * st + 1]);
        }
      },
      progress: (done, total) => out.send(['separate', done / total]),
      cancelled: () => cancelled,
      breathe: () => Future<void>.delayed(Duration.zero),
    );
    if (!ok) {
      for (final w in writers) {
        w.discard();
      }
      return out.send('cancelled');
    }
    for (final w in writers) {
      w.close();
    }
    for (final st in Stem.values) {
      File(p.join(job.outDir, '${st.name}.wav.part')).renameSync(p.join(job.outDir, '${st.name}.wav'));
    }
    out.send('ok');
  } catch (e) {
    for (final w in writers) {
      w.discard();
    }
    out.send('$e');
  } finally {
    runner?.release();
    control.close();
  }
}
