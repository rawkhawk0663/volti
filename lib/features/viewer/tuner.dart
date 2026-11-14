import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_recorder/flutter_recorder.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../../app/error_log.dart';
import '../../app/l10n.dart';
import '../../core/audio/pitch.dart';

/// Was das Stimmgerät gerade hört.
@immutable
class TunerReading {
  const TunerReading(this.hz, this.midi, this.cents);
  final double hz;
  final int midi;
  final double cents;
}

/// Stimmgerät (Mikrofon) und Stimmton (Lautsprecher).
///
/// Das Mikrofon läuft nur, solange das Stimmgerät offen ist
/// ([startListening]/[stopListening]). Der Kammerton [a4] gilt für beide.
class Tuner extends ChangeNotifier {
  Tuner({double a4 = 440, this.onA4Changed}) : _a4 = a4.clamp(minA4, maxA4);

  static const minA4 = 430.0, maxA4 = 450.0;
  static const _rate = 22050;

  /// Wird aufgerufen, wenn der Kammerton geändert wurde (zum Merken).
  final void Function(double a4)? onA4Changed;

  double _a4;
  double get a4 => _a4;
  set a4(double v) {
    final c = (v.clamp(minA4, maxA4) * 2).round() / 2;
    if (c == _a4) return;
    _a4 = c;
    onA4Changed?.call(c);
    notifyListeners();
    final m = _playingMidi;
    if (m != null) playNote(m); // gleich in der neuen Stimmung hören
  }

  bool _disposed = false;

  // ------------------------------------------------------------ Stimmgerät
  final ValueNotifier<TunerReading?> reading = ValueNotifier(null);

  bool _listening = false;
  bool get listening => _listening;

  /// Fehler beim Öffnen des Mikrofons (für die Anzeige).
  String? micError;

  /// Seit dem Start noch nichts gehört (vielleicht ist das Mikrofon gesperrt).
  bool quiet = false;

  StreamSubscription<AudioDataContainer>? _sub;
  final _buffer = Float32List(2048);
  int _filled = 0, _sinceAnalysis = 0;
  final _smoother = PitchSmoother();
  DateTime _lastSound = DateTime.now();
  Timer? _quietTimer;
  int _misses = 0;

  Future<void> startListening() async {
    if (_listening) return;
    _listening = true;
    micError = null;
    quiet = false;
    notifyListeners();
    try {
      if (Platform.isAndroid && !await _askMicPermission()) {
        throw Exception(tr('Volti darf das Mikrofon nicht benutzen.', 'Volti is not allowed to use the microphone.'));
      }
      final rec = Recorder.instance;
      if (!rec.isInitialized) {
        await rec.init(
          format: PCMFormat.f32le,
          sampleRate: _rate,
          channels: RecorderChannels.mono,
          androidInputPreset: AndroidInputPreset.unprocessed,
        );
      }
      if (!_listening) return;
      rec.start();
      _sub = rec.uint8ListStream.listen(_onData);
      rec.startStreamingData();
      _lastSound = DateTime.now();
      _quietTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final q = DateTime.now().difference(_lastSound) > const Duration(seconds: 5);
        if (q != quiet) {
          quiet = q;
          notifyListeners();
        }
      });
    } catch (e) {
      ErrorLog.record(e, null, where: 'Stimmgerät');
      micError = tr('Das Mikrofon liess sich nicht öffnen. ($e)', 'The microphone could not be opened. ($e)');
      await stopListening(keepError: true);
    }
  }

  Future<void> stopListening({bool keepError = false}) async {
    if (!_listening && _sub == null) return;
    _listening = false;
    _quietTimer?.cancel();
    await _sub?.cancel();
    _sub = null;
    try {
      final rec = Recorder.instance;
      if (rec.isInitialized) {
        rec.stopStreamingData();
        rec.deinit(); // Mikrofon ganz freigeben (Windows zeigt sonst das Symbol)
      }
    } catch (_) {}
    _filled = 0;
    _smoother.reset();
    if (!keepError) micError = null;
    if (!_disposed) {
      reading.value = null;
      notifyListeners();
    }
  }

  void _onData(AudioDataContainer data) {
    // Die Daten werden vom Empfänger wiederverwendet: sofort kopieren.
    final bytes = data.rawData;
    final bd = ByteData.sublistView(bytes);
    final n = bytes.length ~/ 4;
    if (n == 0) return;
    if (n >= _buffer.length) {
      for (var i = 0; i < _buffer.length; i++) {
        _buffer[i] = bd.getFloat32((n - _buffer.length + i) * 4, Endian.little);
      }
      _filled = _buffer.length;
    } else {
      // Nach links schieben, neue Werte hinten anhängen.
      _buffer.setRange(0, _buffer.length - n, _buffer, n);
      for (var i = 0; i < n; i++) {
        _buffer[_buffer.length - n + i] = bd.getFloat32(i * 4, Endian.little);
      }
      _filled = (_filled + n).clamp(0, _buffer.length);
    }
    _sinceAnalysis += n;
    // Etwa 15 Mal pro Sekunde auswerten.
    if (_filled < _buffer.length || _sinceAnalysis < _rate ~/ 15) return;
    _sinceAnalysis = 0;
    _analyse();
  }

  void _analyse() {
    final hz = detectPitch(_buffer, _rate);
    if (hz != null) {
      _lastSound = DateTime.now();
      _misses = 0;
      final smooth = _smoother.add(hz)!;
      final n = nearestNote(smooth, a4: _a4);
      reading.value = TunerReading(smooth, n.midi, n.cents);
    } else if (++_misses > 8) {
      // Ein gutes halbe Sekunde nichts: Anzeige leeren (Ton ist verklungen).
      _smoother.reset();
      reading.value = null;
    }
  }

  static const _micChannel = MethodChannel('volti/mic');

  Future<bool> _askMicPermission() async {
    try {
      return await _micChannel.invokeMethod<bool>('request') ?? false;
    } catch (_) {
      return true; // ältere Fassung ohne Abfrage: einfach versuchen
    }
  }

  /// Windows: Datenschutz-Einstellungen für das Mikrofon öffnen.
  static Future<void> openMicSettings() async {
    if (Platform.isWindows) await Process.run('explorer.exe', ['ms-settings:privacy-microphone']);
  }

  // ------------------------------------------------------------- Stimmton
  PipeSound _sound = PipeSound.soft;
  PipeSound get sound => _sound;
  set sound(PipeSound s) {
    if (s == _sound) return;
    _sound = s;
    notifyListeners();
    final m = _playingMidi;
    if (m != null) playNote(m);
  }

  int? _playingMidi;
  int? get playingMidi => _playingMidi;
  String? pipeError;

  AudioSource? _source;
  SoundHandle? _handle;
  Timer? _endTimer;
  int _generation = 0;

  /// Note [midi] spielen (läuft schon dieselbe: anhalten).
  Future<void> toggleNote(int midi) => _playingMidi == midi ? stopNote() : playNote(midi);

  Future<void> playNote(int midi) async {
    final gen = ++_generation;
    _playingMidi = midi;
    pipeError = null;
    notifyListeners();
    try {
      final soloud = SoLoud.instance;
      if (!soloud.isInitialized) await soloud.init(bufferSize: 512);
      final wav = buildPipeTone(noteFrequency(midi, a4: _a4), _sound);
      final source = await soloud.loadMem('stimmton-$gen.wav', wav);
      if (gen != _generation) {
        await soloud.disposeSource(source);
        return;
      }
      await _stopSound();
      _source = source;
      final looping = _sound == PipeSound.soft;
      final h = soloud.play(source, looping: looping, volume: looping ? 0 : 1);
      _handle = h;
      if (looping) {
        // Sanft einblenden (kein Knacken).
        soloud.fadeVolume(h, 1, const Duration(milliseconds: 40));
      } else {
        // Gezupfte Saite: klingt von selbst aus.
        _endTimer?.cancel();
        _endTimer = Timer(const Duration(seconds: 4), () {
          if (gen == _generation) {
            _playingMidi = null;
            if (!_disposed) notifyListeners();
          }
        });
      }
    } catch (e) {
      pipeError = tr(
        'Der Ton konnte nicht abgespielt werden. Sind Lautsprecher oder Kopfhörer eingeschaltet?',
        'The sound could not be played. Are speakers or headphones switched on?',
      );
      _playingMidi = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> stopNote() async {
    _generation++;
    _playingMidi = null;
    _endTimer?.cancel();
    if (!_disposed) notifyListeners();
    await _stopSound();
  }

  Future<void> _stopSound() async {
    final h = _handle, s = _source;
    _handle = null;
    _source = null;
    try {
      final soloud = SoLoud.instance;
      if (h != null && soloud.getIsValidVoiceHandle(h)) {
        // Sanft ausblenden, dann anhalten.
        soloud.fadeVolume(h, 0, const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await soloud.stop(h);
      }
      if (s != null) await soloud.disposeSource(s);
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _endTimer?.cancel();
    stopListening();
    stopNote();
    reading.dispose();
    super.dispose();
  }
}
