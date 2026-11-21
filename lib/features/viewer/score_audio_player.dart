import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path/path.dart' as p;

import '../../core/audio/stem_service.dart';

import '../../app/l10n.dart';

/// Spielt die Aufnahme eines Stücks ab (zum Mitspielen).
///
/// * Wird ein Stück geöffnet, lädt [load] seine Aufnahme schon im Voraus,
///   damit „Abspielen“ sofort klingt.
/// * Tempo ([speed]) und Tonhöhe ([semitones]) lassen sich unabhängig
///   ändern: Die Geschwindigkeit verändert auch die Tonhöhe, ein Tonhöhen-
///   Filter gleicht das wieder aus.
/// * Schleife von A bis B zum Üben einer Stelle.
/// * Getrennte Spuren ([loadStems]): Beim Transponieren spielen Schlagzeug
///   und Rest als zwei gleichzeitige Stimmen. Nur der Rest wird in der
///   Tonhöhe verschoben, das Schlagzeug klingt so natürlich. Ohne
///   Transponieren spielt immer das Original.
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
    await loadStems(stems?.$1, stems?.$2);
  }

  /// Pfad der geladenen Aufnahme (null = keine).
  String? get path => _path;
  String? _path;

  /// Fehlermeldung (Datei fehlt, Format unbekannt …).
  String? error;

  bool get loading => _loading;
  bool _loading = false;

  bool get ready => _source != null;

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

  /// Getrennte Spuren (Schlagzeug und Rest), null = keine.
  AudioSource? _drums, _rest;
  SoundHandle? _drumsHandle;
  String? _stemsKey;

  /// Spuren geladen: Transponieren lässt das Schlagzeug unverändert.
  bool get hasStems => _drums != null && _rest != null;
  Timer? _ticker;
  int _generation = 0;
  bool _disposed = false;

  static const minSpeed = 0.5, maxSpeed = 1.5;
  static const maxSemitones = 6;

  SoLoud get _soloud => SoLoud.instance;

  /// Getrennte Spuren laden ([drums], [rest]: WAV-Dateien) bzw. mit null
  /// entfernen. Gilt ab dem nächsten Start der Wiedergabe.
  Future<void> loadStems(String? drums, String? rest) async {
    if (drums == _stemsKey && (drums == null || hasStems)) return;
    final position = this.position.value;
    final wasPlaying = _playing;
    if (wasPlaying) await pause();
    await _unloadStems();
    if (drums != null && rest != null) {
      try {
        if (!_soloud.isInitialized) await _soloud.init(bufferSize: 512);
        // Von der Festplatte lesen statt alles in den Speicher.
        _drums = await _soloud.loadFile(drums, mode: LoadMode.disk);
        _rest = await _soloud.loadFile(rest, mode: LoadMode.disk);
        _stemsKey = drums;
      } catch (e) {
        debugPrint('Spuren: $e');
        await _unloadStems();
      }
    }
    this.position.value = position;
    if (wasPlaying) await play();
    _notify();
  }

  Future<void> _unloadStems() async {
    _stopVoice();
    for (final s in [_drums, _rest]) {
      if (s == null) continue;
      try {
        await _soloud.disposeSource(s);
      } catch (_) {}
    }
    _drums = _rest = null;
    _stemsKey = null;
  }

  /// Aufnahme laden (ohne abzuspielen). Gleicher Pfad: nichts zu tun.
  /// null entlädt die bisherige.
  Future<void> load(String? newPath) async {
    if (newPath == _path && (_source != null || _loading)) return;
    final gen = ++_generation;
    await _unload();
    await _unloadStems();
    _path = newPath;
    error = null;
    _length = Duration.zero;
    position.value = Duration.zero;
    _loopA = _loopB = null;
    if (newPath == null) {
      _notify();
      return;
    }
    _loading = true;
    _notify();
    try {
      if (!_soloud.isInitialized) await _soloud.init(bufferSize: 512);
      final source = await _soloud.loadFile(newPath);
      if (gen != _generation) {
        await _soloud.disposeSource(source);
        return;
      }
      _source = source;
      _length = _soloud.getLength(source);
      // Getrennte Spuren dazu (falls schon einmal getrennt); Spuren von
      // gelöschten Aufnahmen wegräumen.
      unawaited(_adoptStems(newPath));
      unawaited(StemService.instance.prune(p.dirname(newPath)));
    } catch (e) {
      if (gen != _generation) return;
      error = tr(
        'Die Aufnahme konnte nicht geladen werden. Fehlt die Datei noch (Abgleich), oder ist das Format unbekannt?',
        'The recording could not be loaded. Is the file still missing (sync), or is the format unknown?',
      );
      debugPrint('Audio: $e');
    }
    if (gen == _generation) {
      _loading = false;
      _notify();
    }
  }

  Future<void> toggle() => _playing ? pause() : play();

  Future<void> play() async {
    final source = _source;
    if (source == null) return;
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
    _notify();
  }

  /// Zum Anfang (bzw. zum Anfang der Schleife).
  void rewind() => seek(looping ? _loopA! : Duration.zero);

  void seek(Duration to) {
    final d = _clampTime(to);
    position.value = d;
    final h = _handle;
    if (h != null && _soloud.getIsValidVoiceHandle(h)) {
      for (final v in [h, ?_drumsHandle]) {
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

  /// Beim Transponieren mit Spuren: Rest verschoben, Schlagzeug nicht.
  bool get _splitVoices => hasStems && _semitones != 0;

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
    if (_splitVoices) {
      _handle = _voice(_rest!, from, _semitones);
      _drumsHandle = _voice(_drums!, from, 0);
    } else {
      _handle = _voice(_source!, from, _semitones);
    }
    if (!paused) _setPause(false);
  }

  /// Alle Stimmen gleichzeitig anhalten bzw. weiterspielen.
  void _setPause(bool pause) {
    final h = _handle;
    if (h == null) return;
    final d = _drumsHandle;
    if (d == null) {
      _soloud.setPause(h, pause);
      return;
    }
    // Als Gruppe, damit beide im selben Augenblick weiterlaufen.
    try {
      final g = _soloud.createVoiceGroup();
      _soloud.addVoicesToGroup(g, [h, d]);
      _soloud.setPause(g, pause);
      _soloud.destroyVoiceGroup(g);
    } catch (_) {
      _soloud.setPause(h, pause);
      _soloud.setPause(d, pause);
    }
  }

  void _restartWithEffects() {
    if (_source == null) {
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
    for (final h in [_handle, _drumsHandle]) {
      if (h == null) continue;
      try {
        _soloud.stop(h);
      } catch (_) {}
    }
    _handle = _drumsHandle = null;
  }

  Future<void> _unload() async {
    _ticker?.cancel();
    _playing = false;
    _stopVoice();
    final s = _source;
    _source = null;
    if (s != null) {
      try {
        await _soloud.disposeSource(s);
      } catch (_) {}
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    StemService.instance.stemsChanged.removeListener(_onStemsChanged);
    _generation++;
    _unload();
    _unloadStems();
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
