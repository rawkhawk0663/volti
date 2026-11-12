import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../../app/l10n.dart';

/// Klang des Metronoms.
enum ClickSound {
  soft('Weich', 'Soft'),
  wood('Holzblock', 'Wood block'),
  beep('Piep', 'Beep');

  const ClickSound(this._de, this._en);
  final String _de, _en;
  String get label => tr(_de, _en);

  static ClickSound fromName(String? n) => ClickSound.values.firstWhere((s) => s.name == n, orElse: () => soft);
}

/// Das Metronom.
///
/// Genau im Takt: Es wird **ein ganzer Takt** als Ton erzeugt (Klick auf
/// jedem Schlag, die „Eins“ heller) und als Schleife abgespielt. So bestimmt
/// die Tonausgabe selbst den Abstand der Klicks – auf den Bildpunkt genau,
/// unabhängig davon, wie beschäftigt die App gerade ist.
class Metronome extends ChangeNotifier {
  static const minBpm = 30, maxBpm = 260;
  static const _rate = 44100;

  int _bpm = 100;
  int _beats = 4;
  ClickSound _sound = ClickSound.soft;
  bool _running = false;
  String? error;

  int get bpm => _bpm;
  int get beats => _beats;
  ClickSound get sound => _sound;
  bool get running => _running;

  /// Aktueller Schlag im Takt (0 = die Eins), für die Anzeige.
  final ValueNotifier<int> beat = ValueNotifier(-1);

  AudioSource? _source;
  SoundHandle? _handle;
  Timer? _restart;
  Timer? _ticker;
  DateTime _startedAt = DateTime.now();
  int _generation = 0;
  bool _disposed = false;

  set bpm(int v) {
    final c = v.clamp(minBpm, maxBpm);
    if (c == _bpm) return;
    _bpm = c;
    _changed();
  }

  set beats(int v) {
    final c = v.clamp(1, 12);
    if (c == _beats) return;
    _beats = c;
    _changed();
  }

  set sound(ClickSound s) {
    if (s == _sound) return;
    _sound = s;
    _changed();
  }

  /// Tempo und Takt eines Stücks übernehmen (läuft das Metronom, gleich hörbar).
  void adopt({int? bpm, int? beats}) {
    var changed = false;
    if (bpm != null && bpm.clamp(minBpm, maxBpm) != _bpm) {
      _bpm = bpm.clamp(minBpm, maxBpm);
      changed = true;
    }
    if (beats != null && beats.clamp(1, 12) != _beats) {
      _beats = beats.clamp(1, 12);
      changed = true;
    }
    if (changed) _changed();
  }

  void _changed() {
    notifyListeners();
    if (!_running) return;
    // Beim Ziehen am Regler nicht bei jedem Schritt neu starten.
    _restart?.cancel();
    _restart = Timer(const Duration(milliseconds: 160), () {
      if (_running) _play();
    });
  }

  // ----------------------------------------------------------- Antippen
  final List<DateTime> _taps = [];

  /// Tempo durch Antippen: der Abstand der letzten Tipps ergibt das Tempo.
  void tap() {
    final now = DateTime.now();
    if (_taps.isNotEmpty && now.difference(_taps.last) > const Duration(seconds: 2)) _taps.clear();
    _taps.add(now);
    if (_taps.length > 6) _taps.removeAt(0);
    if (_taps.length < 2) return;
    final ms = _taps.last.difference(_taps.first).inMicroseconds / 1000 / (_taps.length - 1);
    if (ms > 0) bpm = (60000 / ms).round();
  }

  // ---------------------------------------------------------- Abspielen
  Future<void> toggle() => _running ? stop() : start();

  Future<void> start() async {
    if (_running) return;
    _running = true;
    error = null;
    notifyListeners();
    await _play();
  }

  Future<void> stop() async {
    _running = false;
    _restart?.cancel();
    _ticker?.cancel();
    beat.value = -1;
    _generation++;
    await _stopSound();
    if (!_disposed) notifyListeners();
  }

  Future<void> _stopSound() async {
    final h = _handle, s = _source;
    _handle = null;
    _source = null;
    try {
      if (h != null) await SoLoud.instance.stop(h);
      if (s != null) await SoLoud.instance.disposeSource(s);
    } catch (_) {}
  }

  Future<void> _play() async {
    final gen = ++_generation;
    try {
      final soloud = SoLoud.instance;
      if (!soloud.isInitialized) await soloud.init(bufferSize: 512);
      final wav = buildBar(_bpm, _beats, _sound);
      final source = await soloud.loadMem('metronom-$gen.wav', wav);
      if (gen != _generation || !_running) {
        await soloud.disposeSource(source);
        return;
      }
      await _stopSound();
      _source = source;
      _handle = soloud.play(source, looping: true);
      _startedAt = DateTime.now();
      _startTicker();
    } catch (e) {
      error = tr(
        'Der Ton konnte nicht abgespielt werden. Sind Lautsprecher oder Kopfhörer eingeschaltet?',
        'The sound could not be played. Are speakers or headphones switched on?',
      );
      debugPrint(tr('Metronom: $e', 'Metronome: $e'));
      _running = false;
      _ticker?.cancel();
      if (!_disposed) notifyListeners();
    }
  }

  /// Anzeige des Schlags (ungefähr – der Ton selbst ist genau).
  void _startTicker() {
    _ticker?.cancel();
    final beatUs = 60000000 / _bpm;
    _ticker = Timer.periodic(const Duration(milliseconds: 15), (_) {
      final us = DateTime.now().difference(_startedAt).inMicroseconds;
      final b = (us / beatUs).floor() % _beats;
      if (beat.value != b) beat.value = b;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _restart?.cancel();
    _ticker?.cancel();
    _generation++;
    _stopSound();
    beat.dispose();
    super.dispose();
  }

  // ------------------------------------------------------ Ton erzeugen
  /// Ein ganzer Takt als WAV-Datei (16 Bit, mono): ein Klick pro Schlag,
  /// die Eins heller (bei mehr als einem Schlag pro Takt).
  @visibleForTesting
  static Uint8List buildBar(int bpm, int beats, ClickSound sound) {
    final beatSamples = (_rate * 60 / bpm).round();
    final total = beatSamples * beats;
    final samples = Float64List(total);
    for (var b = 0; b < beats; b++) {
      final accent = b == 0 && beats > 1;
      final click = _click(sound, accent);
      final start = b * beatSamples;
      for (var i = 0; i < click.length && start + i < total; i++) {
        samples[start + i] += click[i];
      }
    }
    final data = ByteData(44 + total * 2);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    data.setUint32(4, 36 + total * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little); // PCM
    data.setUint16(22, 1, Endian.little); // mono
    data.setUint32(24, _rate, Endian.little);
    data.setUint32(28, _rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    str(36, 'data');
    data.setUint32(40, total * 2, Endian.little);
    for (var i = 0; i < total; i++) {
      data.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    }
    return data.buffer.asUint8List();
  }

  /// Ein einzelner Klick.
  /// * Weich: runder, kurzer Ton mit sanftem Anschlag (angenehm über längere Zeit).
  /// * Holzblock: zwei Teiltöne wie ein Holzblock.
  /// * Piep: klassischer Piepton.
  static Float64List _click(ClickSound sound, bool accent) {
    switch (sound) {
      case ClickSound.soft:
        final f = accent ? 1568.0 : 1046.5; // G6 / C6
        return _tone(0.055, (t) {
          final env = math.min(1.0, t / 0.0015) * math.exp(-t / 0.012);
          return env * (0.75 * math.sin(2 * math.pi * f * t) + 0.25 * math.sin(2 * math.pi * f * 2 * t));
        });
      case ClickSound.wood:
        final f = accent ? 1250.0 : 900.0;
        return _tone(0.07, (t) {
          final env = math.min(1.0, t / 0.0008) * math.exp(-t / 0.018);
          return env * (0.6 * math.sin(2 * math.pi * f * t) + 0.4 * math.sin(2 * math.pi * f * 2.76 * t));
        });
      case ClickSound.beep:
        final f = accent ? 1320.0 : 880.0;
        return _tone(0.06, (t) {
          final env = math.min(1.0, math.min(t / 0.003, (0.06 - t) / 0.01));
          return env * 0.7 * math.sin(2 * math.pi * f * t);
        });
    }
  }

  static Float64List _tone(double seconds, double Function(double t) f) {
    final n = (seconds * _rate).round();
    final out = Float64List(n);
    for (var i = 0; i < n; i++) {
      out[i] = 0.8 * f(i / _rate);
    }
    return out;
  }
}
