import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

/// Rohe Tondaten einer Datei (32-Bit-Gleitkomma, verschachtelt).
class RawAudio {
  const RawAudio(this.path, this.sampleRate, this.channels);
  final String path;
  final int sampleRate;
  final int channels;
}

typedef _DecodeNative =
    ffi.Int32 Function(ffi.Pointer<Utf16>, ffi.Pointer<Utf16>, ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Int32>);
typedef _DecodeDart = int Function(ffi.Pointer<Utf16>, ffi.Pointer<Utf16>, ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Int32>);

/// Wandelt [input] (MP3, M4A/AAC, WAV, FLAC …) mit den Decodern des Systems
/// in rohe Tondaten nach [output] um.
///
/// * Windows: Media Foundation im Programm selbst (`VoltiDecodeAudio` in
///   `windows/runner/audio_decode.cpp`), über FFI. Blockiert, deshalb nur in
///   einem Hintergrund-Isolate aufrufen ([decodeAudioWindows]).
/// * Android: MediaCodec über den Kanal `volti/audio` (eigener Thread).
/// * Linux (nur zum Testen): ffmpeg.
Future<RawAudio> decodeAudio(String input, String output) async {
  if (Platform.isAndroid) {
    final r = await const MethodChannel('volti/audio').invokeMapMethod<String, int>('decode', {
      'input': input,
      'output': output,
    });
    return RawAudio(output, r!['rate']!, r['channels']!);
  }
  if (Platform.isWindows) return decodeAudioWindows(input, output);
  // Linux/macOS: ffmpeg (Testumgebung).
  final p = await Process.run('ffmpeg', ['-v', 'error', '-y', '-i', input, '-vn', '-f', 'f32le', '-ac', '2', output]);
  if (p.exitCode != 0) throw Exception('ffmpeg: ${p.stderr}');
  final probe = await Process.run('ffprobe', [
    '-v', 'error', '-select_streams', 'a:0', '-show_entries', 'stream=sample_rate', '-of', 'csv=p=0', input, //
  ]);
  return RawAudio(output, int.parse((probe.stdout as String).trim().split(RegExp(r'[,\s]')).first), 2);
}

/// Windows-Teil von [decodeAudio] (synchron, für ein Hintergrund-Isolate).
RawAudio decodeAudioWindows(String input, String output) {
  final fn = ffi.DynamicLibrary.executable().lookupFunction<_DecodeNative, _DecodeDart>('VoltiDecodeAudio');
  final inPtr = input.toNativeUtf16(), outPtr = output.toNativeUtf16();
  final rate = calloc<ffi.Int32>(), ch = calloc<ffi.Int32>();
  try {
    final code = fn(inPtr, outPtr, rate, ch);
    if (code != 0) {
      throw Exception('Umwandeln nicht möglich (0x${(code & 0xFFFFFFFF).toRadixString(16)})');
    }
    return RawAudio(output, rate.value, ch.value);
  } finally {
    calloc.free(inPtr);
    calloc.free(outPtr);
    calloc.free(rate);
    calloc.free(ch);
  }
}

/// Liest rohe Tondaten als Stereo mit [targetRate] (Mono wird verdoppelt,
/// mehr als zwei Kanäle: die ersten beiden).
(Float32List, Float32List) readStereo(RawAudio raw, {int targetRate = 44100}) {
  final bytes = File(raw.path).readAsBytesSync();
  final data = bytes.buffer.asFloat32List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 4);
  final ch = math.max(1, raw.channels);
  final frames = data.length ~/ ch;
  var l = Float32List(frames), r = Float32List(frames);
  for (var i = 0; i < frames; i++) {
    l[i] = data[i * ch];
    r[i] = data[i * ch + (ch > 1 ? 1 : 0)];
  }
  if (raw.sampleRate != targetRate) {
    l = resample(l, raw.sampleRate, targetRate);
    r = resample(r, raw.sampleRate, targetRate);
  }
  return (l, r);
}

/// Abtastrate ändern (gefenstertes Sinc, 32 Stützstellen je Seite). Die
/// Filterwerte werden je Bruchteil einmal vorberechnet (bei 48 → 44,1 kHz
/// sind es 147 verschiedene).
Float32List resample(Float32List x, int from, int to) {
  if (from == to || x.isEmpty) return x;
  const taps = 32;
  int gcd(int a, int b) => b == 0 ? a : gcd(b, a % b);
  final g = gcd(from, to);
  final up = to ~/ g, down = from ~/ g;
  final cutoff = math.min(1.0, to / from) * 0.97;
  // Filter je Bruchteil p/up: Werte für k = mitte − taps + 1 … mitte + taps.
  final phases = math.min(up, 4096);
  final table = Float64List(phases * 2 * taps);
  for (var p = 0; p < phases; p++) {
    final frac = p / phases;
    var norm = 0.0;
    for (var j = 0; j < 2 * taps; j++) {
      final d = frac + taps - 1 - j;
      final arg = math.pi * d * cutoff;
      final sinc = arg.abs() < 1e-9 ? 1.0 : math.sin(arg) / arg;
      final wpos = (d + taps) / (2 * taps);
      final w = 0.42 - 0.5 * math.cos(2 * math.pi * wpos) + 0.08 * math.cos(4 * math.pi * wpos);
      table[p * 2 * taps + j] = sinc * w;
      norm += sinc * w;
    }
    for (var j = 0; j < 2 * taps; j++) {
      table[p * 2 * taps + j] /= norm;
    }
  }
  final n = (x.length * up) ~/ down;
  final out = Float32List(n);
  final last = x.length - 1;
  for (var i = 0; i < n; i++) {
    final num = i * down;
    final center = num ~/ up;
    final p = up <= phases ? num % up : ((num % up) * phases) ~/ up;
    final row = p * 2 * taps;
    final first = center - taps + 1;
    var sum = 0.0;
    if (first >= 0 && first + 2 * taps - 1 <= last) {
      for (var j = 0; j < 2 * taps; j++) {
        sum += x[first + j] * table[row + j];
      }
    } else {
      for (var j = 0; j < 2 * taps; j++) {
        final k = first + j;
        if (k >= 0 && k <= last) sum += x[k] * table[row + j];
      }
    }
    out[i] = sum;
  }
  return out;
}

/// Schreibt eine Stereo-WAV-Datei (16 Bit) Stück für Stück.
class WavWriter {
  WavWriter(this.path, {this.sampleRate = 44100}) : _file = File(path).openSync(mode: FileMode.write) {
    _file.writeFromSync(Uint8List(44)); // Kopf kommt am Schluss
  }

  final String path;
  final int sampleRate;
  final RandomAccessFile _file;
  int _frames = 0;

  void add(Float32List left, Float32List right) {
    final n = left.length;
    final b = ByteData(n * 4);
    for (var i = 0; i < n; i++) {
      b.setInt16(i * 4, (left[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
      b.setInt16(i * 4 + 2, (right[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    }
    _file.writeFromSync(b.buffer.asUint8List());
    _frames += n;
  }

  void close() {
    final data = _frames * 4;
    final h = ByteData(44);
    void str(int at, String s) {
      for (var i = 0; i < 4; i++) {
        h.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    h.setUint32(4, 36 + data, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    h.setUint32(16, 16, Endian.little);
    h.setUint16(20, 1, Endian.little); // PCM
    h.setUint16(22, 2, Endian.little); // stereo
    h.setUint32(24, sampleRate, Endian.little);
    h.setUint32(28, sampleRate * 4, Endian.little);
    h.setUint16(32, 4, Endian.little);
    h.setUint16(34, 16, Endian.little);
    str(36, 'data');
    h.setUint32(40, data, Endian.little);
    _file.setPositionSync(0);
    _file.writeFromSync(h.buffer.asUint8List());
    _file.closeSync();
  }

  /// Datei schliessen und wegwerfen (abgebrochen).
  void discard() {
    try {
      _file.closeSync();
    } catch (_) {}
    try {
      File(path).deleteSync();
    } catch (_) {}
  }
}
