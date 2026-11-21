// Das Trenn-Modell: Download der Modell-Datei und Rechnen mit ONNX Runtime.
// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:onnxruntime_v2/onnxruntime_v2.dart';
import 'package:onnxruntime_v2/src/bindings/onnxruntime_bindings_generated.dart' as bg;
import 'package:path/path.dart' as p;

import 'stem_separation.dart';
import 'stft.dart';

/// Die Modell-Datei (Hybrid Transformer Demucs von Meta, MIT-Lizenz),
/// erzeugt mit `tool/make_stem_model.py` und als Vorabversion abgelegt
/// (`.github/workflows/stem_model.yml`).
class StemModelFile {
  StemModelFile._();

  static const tag = 'stem-model-v1';
  static const url = 'https://github.com/rawkhawk0663/volti/releases/download/$tag/htdemucs_core.onnx';
  static const sha256Hex = 'f814be1fa131137ed3a827a2fdb3a1ac6c439100d3c82496868cc4294341c45e';
  static const size = 174264717;

  /// Ablage der Modell-Datei in [supportDir] (nicht abgeglichen).
  static String pathIn(String supportDir) => p.join(supportDir, 'stem-model', '$tag.onnx');

  static bool installed(String supportDir) {
    final f = File(pathIn(supportDir));
    return f.existsSync() && f.lengthSync() == size;
  }

  /// Lädt die Modell-Datei herunter und prüft sie (Prüfsumme). [progress]
  /// bekommt 0..1. Gibt false zurück, wenn [cancelled] vorher true wurde.
  static Future<bool> download(
    String supportDir, {
    void Function(double)? progress,
    bool Function()? cancelled,
  }) async {
    final target = File(pathIn(supportDir));
    await target.parent.create(recursive: true);
    final part = File('${target.path}.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'Volti-App');
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength > 0 ? res.contentLength : size;
      final sink = part.openWrite();
      final hashOut = _DigestSink();
      final hasher = sha256.startChunkedConversion(hashOut);
      var got = 0;
      var stopped = false;
      try {
        await for (final chunk in res) {
          if (cancelled?.call() ?? false) {
            stopped = true;
            break;
          }
          sink.add(chunk);
          hasher.add(chunk);
          got += chunk.length;
          progress?.call(math.min(1, got / total));
        }
      } finally {
        await sink.close();
      }
      if (stopped) {
        await part.delete();
        return false;
      }
      hasher.close();
      if (hashOut.value.toString() != sha256Hex) {
        await part.delete();
        throw Exception('Prüfsumme falsch');
      }
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      return true;
    } finally {
      client.close(force: true);
    }
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Rechnet mit dem Modell (ONNX Runtime, nur Prozessor). Nur in einem
/// Hintergrund-Isolate benutzen: Ein Stück dauert einige Sekunden.
class StemModelRunner {
  StemModelRunner(String modelPath, {int? threads}) {
    OrtEnv.instance.init();
    _optionsPtr = _createOptions(threads ?? defaultThreads);
    _session = _openSession(modelPath);
    _runOptions = OrtRunOptions();
    _mix = calloc<ffi.Float>(_mixCount);
    _mag = calloc<ffi.Float>(_magCount);
  }

  /// Einstellungen für die Sitzung (selbst angelegt, damit [_openSession]
  /// sie direkt übergeben kann).
  ffi.Pointer<bg.OrtSessionOptions> _createOptions(int threads) {
    final out = calloc<ffi.Pointer<bg.OrtSessionOptions>>();
    try {
      OrtStatus.checkOrtStatus(
        _api.CreateSessionOptions.asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<ffi.Pointer<bg.OrtSessionOptions>>)
        >()(out),
      );
      final o = out.value;
      OrtStatus.checkOrtStatus(
        _api.SetIntraOpNumThreads.asFunction<bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, int)>()(
          o,
          threads,
        ),
      );
      OrtStatus.checkOrtStatus(
        _api.SetInterOpNumThreads.asFunction<bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, int)>()(o, 1),
      );
      OrtStatus.checkOrtStatus(
        _api.SetSessionGraphOptimizationLevel.asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, int)
        >()(o, GraphOptimizationLevel.ortEnableAll.value),
      );
      return o;
    } finally {
      calloc.free(out);
    }
  }

  /// Sitzung aus der Modell-Datei. Unter Windows erwartet ONNX Runtime den
  /// Pfad in UTF-16 (`OrtSession.fromFile` übergibt UTF-8, das gab beim
  /// Besitzer „File doesn't exist“ mit Zeichensalat).
  OrtSession _openSession(String path) {
    final name = Platform.isWindows ? path.toNativeUtf16(allocator: calloc).cast<ffi.Char>() : path.toNativeUtf8(allocator: calloc).cast<ffi.Char>();
    final out = calloc<ffi.Pointer<bg.OrtSession>>();
    try {
      OrtStatus.checkOrtStatus(
        _api.CreateSession.asFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtEnv>,
            ffi.Pointer<ffi.Char>,
            ffi.Pointer<bg.OrtSessionOptions>,
            ffi.Pointer<ffi.Pointer<bg.OrtSession>>,
          )
        >()(OrtEnv.instance.ptr, name, _optionsPtr, out),
      );
      return OrtSession.fromAddress(out.value.address);
    } finally {
      calloc.free(name);
      calloc.free(out);
    }
  }

  /// Etwas Luft für die Oberfläche lassen.
  static int get defaultThreads => math.max(1, math.min(8, Platform.numberOfProcessors - 2));

  static const _seg = StemSeparation.defaultSegment;
  static const _mixCount = 2 * _seg;
  static final _frames = DemucsSpectrum(_seg).frames;
  static final _magCount = 4 * DemucsSpectrum.bins * _frames;

  late final ffi.Pointer<bg.OrtSessionOptions> _optionsPtr;
  late final OrtSession _session;
  late final OrtRunOptions _runOptions;
  late final ffi.Pointer<ffi.Float> _mix, _mag;

  bg.OrtApi get _api => OrtEnv.instance.ortApiPtr.ref;

  ffi.Pointer<bg.OrtValue> _tensor(ffi.Pointer<ffi.Float> data, int count, List<int> shape) {
    final shapePtr = calloc<ffi.Int64>(shape.length);
    shapePtr.asTypedList(shape.length).setAll(0, shape);
    final infoPtr = calloc<ffi.Pointer<bg.OrtMemoryInfo>>();
    final valuePtr = calloc<ffi.Pointer<bg.OrtValue>>();
    try {
      OrtStatus.checkOrtStatus(
        _api.AllocatorGetInfo.asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtAllocator>, ffi.Pointer<ffi.Pointer<bg.OrtMemoryInfo>>)
        >()(OrtAllocator.instance.ptr, infoPtr),
      );
      OrtStatus.checkOrtStatus(
        _api.CreateTensorWithDataAsOrtValue.asFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtMemoryInfo>,
            ffi.Pointer<ffi.Void>,
            int,
            ffi.Pointer<ffi.Int64>,
            int,
            int,
            ffi.Pointer<ffi.Pointer<bg.OrtValue>>,
          )
        >()(
          infoPtr.value,
          data.cast(),
          count * 4,
          shapePtr,
          shape.length,
          ONNXTensorElementDataType.float.value,
          valuePtr,
        ),
      );
      return valuePtr.value;
    } finally {
      calloc.free(shapePtr);
      calloc.free(infoPtr);
      calloc.free(valuePtr);
    }
  }

  Float32List _data(OrtValue value, int count) {
    final out = calloc<ffi.Pointer<ffi.Void>>();
    try {
      OrtStatus.checkOrtStatus(
        _api.GetTensorMutableData.asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>, ffi.Pointer<ffi.Pointer<ffi.Void>>)
        >()(value.ptr, out),
      );
      return out.value.cast<ffi.Float>().asTypedList(count);
    } finally {
      calloc.free(out);
    }
  }

  void _release(ffi.Pointer<bg.OrtValue> v) =>
      _api.ReleaseValue.asFunction<void Function(ffi.Pointer<bg.OrtValue>)>()(v);

  /// Passt zu [StemSeparation.run].
  void run(Float32List mix, Float32List mag, void Function(Float32List spec, Float32List wave) use) {
    _mix.asTypedList(_mixCount).setAll(0, mix);
    _mag.asTypedList(_magCount).setAll(0, mag);
    final mixValue = _tensor(_mix, _mixCount, [1, 2, _seg]);
    final magValue = _tensor(_mag, _magCount, [1, 4, DemucsSpectrum.bins, _frames]);
    List<OrtValue?> outputs = const [];
    try {
      outputs = _session.run(_runOptions, {
        'mix': OrtValueTensor.fromAddress(mixValue.address),
        'mag': OrtValueTensor.fromAddress(magValue.address),
      });
      final spec = _data(outputs[0]!, 4 * _magCount);
      final wave = _data(outputs[1]!, 4 * _mixCount);
      use(spec, wave);
    } finally {
      for (final o in outputs) {
        if (o != null) _release(o.ptr);
      }
      _release(mixValue);
      _release(magValue);
    }
  }

  void release() {
    _runOptions.release();
    _session.release();
    _api.ReleaseSessionOptions.asFunction<void Function(ffi.Pointer<bg.OrtSessionOptions>)>()(_optionsPtr);
    calloc.free(_mix);
    calloc.free(_mag);
    OrtEnv.instance.release();
  }
}
