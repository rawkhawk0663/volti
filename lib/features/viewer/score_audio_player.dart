import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path/path.dart' as p;

import '../../core/audio/stem_separation.dart';
import '../../core/audio/stem_service.dart';

import '../../app/audio_engine.dart';
import '../../app/l10n.dart';

/// Spielt die Aufnahme eines Stücks ab (zum Mitspielen).
///
/// * Wird ein Stück geöffnet, merkt sich [load] nur seine Aufnahme. Geladen
///   (ausgepackt) wird sie erst beim Abspielen bzw. wenn das Fenster aufgeht
///   ([ensureLoaded]), und nach einer Minute Pause wieder freigegeben. So
///   kostet ein Songwechsel in der Setlist nichts (früher wurde jedes Mal die
///   ganze Aufnahme ausgepackt, das bremste das Tablet).
/// * Tempo ([speed]) und Tonhöhe ([semitones]) lassen sich unabhängig
///   ändern: Die Geschwindigkeit verändert auch die Tonhöhe, ein Tonhöhen-
///   Filter gleicht das wieder aus.
/// * Schleife von A bis B zum Üben einer Stelle.
/// * Getrennte Spuren ([loadStems]): Dann spielen Schlagzeug, Bass,
///   Instrumente und Gesang als vier gleichzeitige Stimmen, jede mit eigener
///   Lautstärke, stumm oder solo ([setStemVolume], [toggleMute],
///   [toggleSolo]). Beim Transponieren bleibt das Schlagzeug unverändert, das
///   klingt natürlicher.
class ScoreAudioPlayer extends ChangeNotifier {
  ScoreAudioPlayer() {
    StemService.instance.stemsChanged.addListener(_onStemsChanged);
  }

  /// Neue oder gelöschte Spuren zur geladenen Aufnahme übernehmen.
  void _onStemsChanged() {
    final changed = StemService.instance.stemsChanged.value;
    if (changed != null && changed == _path) _adoptStems(changed);
  }

  Future<void> _adoptStems(String audio) async {
    final stems = await StemService.instance.stemsFor(audio);
    if (audio != _path || _disposed) return;
    await loadStems(stems, mixFile: p.join(await StemService.instance.folderFor(audio), 'mix.json'));
  }

  /// Pfad der geladenen Aufnahme (null = keine).
  String? get path => _path;
  String? _path;

  /// Fehlermeldung (Datei fehlt, Format unbekannt …).
  String? error;

  bool get loading => _loading;
  bool _loading = false;

  /// Länge bekannt: Die Bedienung kann angezeigt werden (auch wenn die
  /// Aufnahme nach einer Pause wieder freigegeben ist).
  bool get ready => _length > Duration.zero;

  /// Klänge geladen (Original bzw. die Spuren).
  bool get _loaded => _stemFiles != null ? _stems != null : _source != null;
  Future<void>? _loadingFuture;
  Timer? _sleepTimer;

  Duration get length => _length;
  Duration _length = Duration.zero;

  /// Aktuelle Stelle (wird beim Abspielen laufend nachgeführt).
  final position = ValueNotifier<Duration>(Duration.zero);

  bool get playing => _playing;
  bool _playing = false;

  /// Geschwindigkeit (1 = Original), 0,5 bis 1,5.
  double get speed => _speed;
  double _speed = 1;

  /// Tonhöhe in Halbtönen (0 = Original), −6 bis +6.
  int get semitones => _semitones;
  int _semitones = 0;

  /// Schleife: Anfang und Ende (null = nicht gesetzt).
  Duration? get loopA => _loopA;
  Duration? get loopB => _loopB;
  Duration? _loopA, _loopB;
  bool get looping => _loopA != null && _loopB != null && _loopB! > _loopA!;

  AudioSource? _source;
  SoundHandle? _handle;

  /// Dateien der getrennten Spuren (Reihenfolge [Stem]), null = keine.
  List<String>? _stemFiles;

  /// Geladene Spuren (nur solange gebraucht).
  List<AudioSource>? _stems;
  List<SoundHandle> _stemHandles = const [];
  String? _stemsKey;
  String? _mixFile;

  /// Spuren geladen: Mischpult und natürlicheres Transponieren.
  bool get hasStems => _stemFiles != null;

  /// Mischung je Spur: Lautstärke 0..1, stumm, solo.
  final List<double> stemVolume = List.filled(Stem.values.length, 1.0);
  final List<bool> stemMuted = List.filled(Stem.values.length, false);
  final List<bool> stemSolo = List.filled(Stem.values.length, false);

  /// Ist die Mischung verändert (nicht alles voll, nichts stumm oder solo)?
  bool get mixChanged => stemVolume.any((v) => v != 1) || stemMuted.any((m) => m) || stemSolo.any((s) => s);

  /// Was von Spur [i] gerade zu hören ist (0..1).
  double stemGain(int i) {
    final anySolo = stemSolo.any((s) => s);
    final on = anySolo ? stemSolo[i] : !stemMuted[i];
    return on ? stemVolume[i] : 0;
  }

  void setStemVolume(int i, double v) {
    stemVolume[i] = v.clamp(0.0, 1.0);
    _applyMix();
  }

  void toggleMute(int i) {
    stemMuted[i] = !stemMuted[i];
    _applyMix();
  }

  void toggleSolo(int i) {
    stemSolo[i] = !stemSolo[i];
    _applyMix();
  }

  void resetMix() {
    resetMixValues();
    _applyMix();
  }

  /// Lautstärken sofort setzen (ohne Neustart) und die Mischung merken.
  void _applyMix({bool save = true}) {
    for (var i = 0; i < _stemHandles.length; i++) {
      try {
        _soloud.setVolume(_stemHandles[i], stemGain(i));
      } catch (_) {}
    }
    if (save) _saveMix();
    _notify();
  }

  void _saveMix() {
    final f = _mixFile;
    if (f == null) return;
    try {
      File(f).writeAsStringSync(jsonEncode({'v': stemVolume, 'm': stemMuted, 's': stemSolo}));
    } catch (_) {}
  }

  void _loadMix() {
    resetMixValues();
    final f = _mixFile;
    if (f == null) return;
    try {
      final j = jsonDecode(File(f).readAsStringSync()) as Map<String, dynamic>;
      final v = j['v'] as List, m = j['m'] as List, s = j['s'] as List;
      for (var i = 0; i < stemVolume.length && i < v.length; i++) {
        stemVolume[i] = (v[i] as num).toDouble().clamp(0.0, 1.0);
        stemMuted[i] = m[i] == true;
        stemSolo[i] = s[i] == true;
      }
    } catch (_) {}
  }

  @visibleForTesting
  void resetMixValues() {
    stemVolume.fillRange(0, stemVolume.length, 1);
    stemMuted.fillRange(0, stemMuted.length, false);
    stemSolo.fillRange(0, stemSolo.length, false);
  }

  Timer? _ticker;
  int _generation = 0;
  bool _disposed = false;

  static const minSpeed = 0.5, maxSpeed = 1.5;
  static const maxSemitones = 6;

  SoLoud get _soloud => SoLoud.instance;

  /// Getrennte Spuren übernehmen ([files] in der Reihenfolge von [Stem])
  /// bzw. mit null entfernen. [mixFile] merkt sich die Mischung dieser
  /// Aufnahme. Läuft gerade etwas, geht es mit den Spuren nahtlos weiter.
  Future<void> loadStems(List<String>? files, {String? mixFile}) async {
    final key = files?.first;
    if (key == _stemsKey) return;
    final wasLoaded = _loaded, wasPlaying = _playing;
    if (wasPlaying) await pause();
    await _unloadSources();
    _stemFiles = files != null && files.length == Stem.values.length ? files : null;
    _stemsKey = _stemFiles == null ? null : key;
    _mixFile = _stemFiles == null ? null : mixFile;
    _loadMix();
    if (wasLoaded) await ensureLoaded();
    if (wasPlaying) await play();
    _notify();
  }

  /// Aufnahme merken (ohne sie zu laden). Gleicher Pfad: nichts zu tun.
  /// null vergisst die bisherige.
  Future<void> load(String? newPath) async {
    if (newPath == _path) return;
    ++_generation;
    await _unloadSources();
    _path = newPath;
    error = null;
    _length = Duration.zero;
    position.value = Duration.zero;
    _loopA = _loopB = null;
    _stemFiles = null;
    _stemsKey = _mixFile = null;
    resetMixValues();
    _notify();
    // Gibt es schon getrennte Spuren? (nur nachsehen, nichts laden)
    if (newPath != null) unawaited(_adoptStems(newPath));
  }

  /// Klänge laden, falls nötig (beim Abspielen und wenn das Fenster aufgeht).
  Future<void> ensureLoaded() {
    if (_path == null || _loaded) return Future.value();
    return _loadingFuture ??= _loadSources().whenComplete(() {
      _loadingFuture = null;
    });
  }

  Future<void> _loadSources() async {
    final path = _path!;
    final gen = _generation;
    _loading = true;
    error = null;
    _notify();
    try {
      final soloud = await AudioEngine.use(this);
      final stems = _stemFiles;
      if (stems != null) {
        // Von der Festplatte lesen statt alles in den Speicher; das Original
        // braucht es dann gar nicht.
        final loaded = <AudioSource>[];
        for (final f in stems) {
          loaded.add(await soloud.loadFile(f, mode: LoadMode.disk));
        }
        if (gen != _generation || _stemFiles != stems) {
          for (final s in loaded) {
            await soloud.disposeSource(s);
          }
          return;
        }
        _stems = loaded;
        _length = soloud.getLength(loaded.first);
      } else {
        final source = await soloud.loadFile(path);
        if (gen != _generation || _stemFiles != null) {
          await soloud.disposeSource(source);
          return;
        }
        _source = source;
        _length = soloud.getLength(source);
      }
      _scheduleSleep();
      // Spuren von gelöschten Aufnahmen wegräumen.
      unawaited(StemService.instance.prune(p.dirname(path)));
    } catch (e) {
      if (gen != _generation) return;
      error = tr(
        'Die Aufnahme konnte nicht geladen werden. Fehlt die Datei noch (Abgleich), oder ist das Format unbekannt?',
        'The recording could not be loaded. Is the file still missing (sync), or is the format unknown?',
      );
      debugPrint('Audio: $e');
    } finally {
      if (gen == _generation) {
        _loading = false;
        _notify();
      }
    }
  }

  /// Nach einer Minute ohne Abspielen alles freigeben (spart Speicher, und
  /// die Audio-Technik darf schlafen).
  void _scheduleSleep() {
    _sleepTimer?.cancel();
    _sleepTimer = Timer(const Duration(minutes: 1), () {
      if (_playing || _disposed) return;
      final h = _handle;
      if (h != null && _soloud.isInitialized && _soloud.getIsValidVoiceHandle(h)) {
        position.value = _soloud.getPosition(h);
      }
      unawaited(_unloadSources());
    });
  }

  Future<void> toggle() => _playing ? pause() : play();

  Future<void> play() async {
    _sleepTimer?.cancel();
    await ensureLoaded();
    if (!_loaded || _disposed) return;
    final h = _handle;
    if (h != null && _soloud.getIsValidVoiceHandle(h)) {
      _setPause(false);
    } else {
      var from = position.value;
      if (from >= _length - const Duration(milliseconds: 200)) from = Duration.zero;
      _start(from, paused: false);
    }
    _playing = true;
    _startTicker();
    _notify();
  }

  Future<void> pause() async {
    final h = _handle;
    if (h != null && _soloud.getIsValidVoiceHandle(h)) {
      position.value = _soloud.getPosition(h);
      _setPause(true);
    }
    _playing = false;
    _ticker?.cancel();
    _scheduleSleep();
    _notify();
  }

  /// Zum Anfang (bzw. zum Anfang der Schleife).
  void rewind() => seek(looping ? _loopA! : Duration.zero);

  void seek(Duration to) {
    final d = _clampTime(to);
    position.value = d;
    final h = _handle;
    if (h != null && _soloud.isInitialized && _soloud.getIsValidVoiceHandle(h)) {
      for (final v in _voices) {
        try {
          _soloud.seek(v, d);
        } catch (_) {}
      }
    }
  }

  void skip(Duration by) => seek(position.value + by);

  void setSpeed(double v) {
    final s = (v.clamp(minSpeed, maxSpeed) * 100).round() / 100;
    if (s == _speed) return;
    _speed = s;
    _restartWithEffects();
  }

  void setSemitones(int v) {
    final s = v.clamp(-maxSemitones, maxSemitones);
    if (s == _semitones) return;
    _semitones = s;
    _restartWithEffects();
  }

  void setLoopA() {
    _loopA = position.value;
    if (_loopB != null && _loopB! <= _loopA!) _loopB = null;
    _notify();
  }

  void setLoopB() {
    final b = position.value;
    if (_loopA != null && b <= _loopA!) return;
    _loopB = b;
    _loopA ??= Duration.zero;
    _notify();
  }

  void clearLoop() {
    _loopA = _loopB = null;
    _notify();
  }

  // ------------------------------------------------------------ intern

  Duration _clampTime(Duration d) {
    if (d.isNegative) return Duration.zero;
    return d > _length ? _length : d;
  }

  /// Alle laufenden Stimmen (eine bzw. je Spur eine).
  List<SoundHandle> get _voices => _stemHandles.isNotEmpty ? _stemHandles : [?_handle];

  /// Tonhöhen-Filter einer Quelle vor dem Abspielen ein- bzw. ausschalten.
  void _prepareFilter(AudioSource source, bool on) {
    final filter = source.filters.pitchShiftFilter;
    try {
      if (on && !filter.isActive) filter.activate();
      if (!on && filter.isActive) filter.deactivate();
    } catch (e) {
      debugPrint('Audio-Filter: $e');
    }
  }

  /// Stimme starten (pausiert), Stelle, Tempo und Tonhöhe setzen.
  SoundHandle _voice(AudioSource source, Duration from, int semitones) {
    final shift = math.pow(2, semitones / 12) / _speed;
    final needsFilter = (shift - 1).abs() > 1e-6;
    _prepareFilter(source, needsFilter);
    final h = _soloud.play(source, paused: true);
    try {
      if (from > Duration.zero) _soloud.seek(h, from);
      _soloud.setRelativePlaySpeed(h, _speed);
      // Tempo verschiebt die Tonhöhe mit – hier wieder ausgleichen.
      if (needsFilter) {
        source.filters.pitchShiftFilter.shift(soundHandle: h).value = shift.clamp(0.0, 3.0).toDouble();
      }
    } catch (e) {
      debugPrint('Audio: $e');
    }
    return h;
  }

  /// Neue Stimme(n) starten (Filter müssen vor dem Abspielen gesetzt sein).
  void _start(Duration from, {required bool paused}) {
    _stopVoice();
    final stems = _stems;
    if (stems != null) {
      // Jede Spur eine Stimme; das Schlagzeug wird nicht transponiert.
      _stemHandles = [
        for (var i = 0; i < stems.length; i++) _voice(stems[i], from, i == Stem.drums.index ? 0 : _semitones),
      ];
      _handle = _stemHandles.first;
      _applyMix(save: false);
    } else {
      _handle = _voice(_source!, from, _semitones);
    }
    if (!paused) _setPause(false);
  }

  /// Alle Stimmen gleichzeitig anhalten bzw. weiterspielen.
  void _setPause(bool pause) {
    final voices = _voices;
    if (voices.isEmpty) return;
    if (voices.length == 1) {
      _soloud.setPause(voices.first, pause);
      return;
    }
    // Als Gruppe, damit alle im selben Augenblick weiterlaufen.
    try {
      final g = _soloud.createVoiceGroup();
      _soloud.addVoicesToGroup(g, voices);
      _soloud.setPause(g, pause);
      _soloud.destroyVoiceGroup(g);
    } catch (_) {
      for (final v in voices) {
        _soloud.setPause(v, pause);
      }
    }
  }

  void _restartWithEffects() {
    if (!_loaded) {
      _notify();
      return;
    }
    final h = _handle;
    if (h != null && _soloud.getIsValidVoiceHandle(h)) position.value = _soloud.getPosition(h);
    if (_playing) _start(position.value, paused: false);
    _notify();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
  }

  void _tick() {
    final h = _handle;
    if (h == null || !_soloud.getIsValidVoiceHandle(h)) {
      // Zu Ende gespielt.
      _stopVoice();
      if (looping) {
        _start(_loopA!, paused: false);
        position.value = _loopA!;
        return;
      }
      _playing = false;
      _ticker?.cancel();
      position.value = Duration.zero;
      _scheduleSleep();
      _notify();
      return;
    }
    final pos = _soloud.getPosition(h);
    if (looping && pos >= _loopB!) {
      seek(_loopA!);
      return;
    }
    position.value = pos;
  }

  void _stopVoice() {
    if (!_soloud.isInitialized) {
      _handle = null;
      _stemHandles = const [];
      return;
    }
    for (final h in {..._stemHandles, ?_handle}) {
      try {
        _soloud.stop(h);
      } catch (_) {}
    }
    _handle = null;
    _stemHandles = const [];
  }

  /// Alle geladenen Klänge freigeben und die Audio-Technik abmelden.
  Future<void> _unloadSources() async {
    _ticker?.cancel();
    _sleepTimer?.cancel();
    _playing = false;
    _stopVoice();
    final all = [?_source, ...?_stems];
    _source = null;
    _stems = null;
    if (_soloud.isInitialized) {
      for (final s in all) {
        try {
          await _soloud.disposeSource(s);
        } catch (_) {}
      }
    }
    AudioEngine.done(this);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    StemService.instance.stemsChanged.removeListener(_onStemsChanged);
    _generation++;
    _unloadSources();
    position.dispose();
    super.dispose();
  }
}

/// „1:05“ bzw. „1:02:05“.
String formatTime(Duration d) {
  final s = d.inSeconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}
