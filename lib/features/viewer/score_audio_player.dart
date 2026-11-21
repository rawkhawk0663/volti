import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path/path.dart' as p;

import '../../core/audio/stem_separation.dart';
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

  /// Getrennte Spuren in der Reihenfolge von [Stem], null = keine.
  List<AudioSource>? _stems;
  List<SoundHandle> _stemHandles = const [];
  String? _stemsKey;
  String? _mixFile;

  /// Spuren geladen: Mischpult und natürlicheres Transponieren.
  bool get hasStems => _stems != null;

  /// Mischung je Spur: Lautstärke 0..1, stumm, solo.
  final List<double> stemVolume = List.filled(Stem.values.length, 1.0);
  final List<bool> stemMuted = List.filled(Stem.values.length, false);
  final List<bool> stemSolo = List.filled(Stem.values.length, false);

  /// Ist die Mischung verändert (nicht alles voll, nichts stumm oder solo)?
  bool get mixChanged =>
      stemVolume.any((v) => v != 1) || stemMuted.any((m) => m) || stemSolo.any((s) => s);

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

  /// Getrennte Spuren laden ([files] in der Reihenfolge von [Stem]) bzw.
  /// mit null entfernen. [mixFile] merkt sich die Mischung dieser Aufnahme.
  Future<void> loadStems(List<String>? files, {String? mixFile}) async {
    final key = files?.first;
    if (key == _stemsKey && (key == null || hasStems)) return;
    final position = this.position.value;
    final wasPlaying = _playing;
    if (wasPlaying) await pause();
    await _unloadStems();
    if (files != null && files.length == Stem.values.length) {
      try {
        if (!_soloud.isInitialized) await _soloud.init(bufferSize: 512);
        // Von der Festplatte lesen statt alles in den Speicher.
        _stems = [for (final f in files) await _soloud.loadFile(f, mode: LoadMode.disk)];
        _stemsKey = key;
        _mixFile = mixFile;
        _loadMix();
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
    for (final s in _stems ?? const <AudioSource>[]) {
      try {
        await _soloud.disposeSource(s);
      } catch (_) {}
    }
    _stems = null;
    _stemsKey = null;
    _mixFile = null;
    resetMixValues();
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
    for (final h in {..._stemHandles, ?_handle}) {
      try {
        _soloud.stop(h);
      } catch (_) {}
    }
    _handle = null;
    _stemHandles = const [];
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
