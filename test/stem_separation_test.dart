import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:volti/core/audio/pcm.dart';
import 'package:volti/core/audio/stem_separation.dart';
import 'package:volti/core/audio/stft.dart';

void main() {
  test('FFT stimmt mit der langsamen Rechnung überein', () {
    const n = 16;
    final rnd = math.Random(1);
    final xr = List.generate(n, (_) => rnd.nextDouble() - 0.5);
    final xi = List.generate(n, (_) => rnd.nextDouble() - 0.5);
    final re = Float64List.fromList(xr), im = Float64List.fromList(xi);
    Fft(n).transform(re, im);
    for (var k = 0; k < n; k++) {
      var sr = 0.0, si = 0.0;
      for (var t = 0; t < n; t++) {
        final a = -2 * math.pi * k * t / n;
        sr += xr[t] * math.cos(a) - xi[t] * math.sin(a);
        si += xr[t] * math.sin(a) + xi[t] * math.cos(a);
      }
      expect(re[k], closeTo(sr, 1e-9));
      expect(im[k], closeTo(si, 1e-9));
    }
    Fft(n).transform(re, im, inverse: true);
    for (var t = 0; t < n; t++) {
      expect(re[t] / n, closeTo(xr[t], 1e-9));
    }
  });

  test('Spektrum hin und zurück ergibt wieder den Ton (beide Kanäle)', () {
    const len = 20000;
    // Ohne Anteile bei der höchsten Frequenz (die lässt das Modell weg).
    final l = Float32List.fromList(List.generate(len, (i) => math.sin(i * 0.01) + 0.2 * math.sin(i * 0.9)));
    final r = Float32List.fromList(List.generate(len, (i) => math.cos(i * 0.003) * 0.5));
    final s = DemucsSpectrum(len);
    final spec = s.forward(l, r);
    expect(spec.length, 4 * DemucsSpectrum.bins * s.frames);
    final outL = Float64List(len), outR = Float64List(len);
    s.inverse(spec, 0, outL, outR);
    // Am Rand fehlen dem Modell zwei Rahmen; dort weicht es auch im
    // Original ab. Die Mitte muss genau stimmen.
    var err = 0.0;
    for (var i = 3000; i < len - 3000; i++) {
      err = math.max(err, (outL[i] - l[i]).abs());
      err = math.max(err, (outR[i] - r[i]).abs());
    }
    expect(err, lessThan(1e-4));
  });

  test('Rand verhält sich genau wie im Original-Modell', () {
    // Werte aus PyTorch: _ispec(_spec(x)) von htdemucs, x = sin(i · 0,01).
    const len = 20000;
    final l = Float32List.fromList(List.generate(len, (i) => math.sin(i * 0.01)));
    final s = DemucsSpectrum(len);
    final outL = Float64List(len), outR = Float64List(len);
    s.inverse(s.forward(l, Float32List(len)), 0, outL, outR);
    const expected = {0: 0.0, 100: 0.4813, 1000: -0.5348, 5000: -0.2624, 19000: 0.9978, 19999: -0.7175};
    for (final e in expected.entries) {
      expect(outL[e.key], closeTo(e.value, 1e-4), reason: 'Stelle ${e.key}');
    }
  });

  test('Trennen mit einem Schein-Modell gibt den Ton über alle Stückgrenzen zurück', () async {
    // Echte Stücklänge (7,8 s): An den Stückrändern fehlen dem Modell
    // Rahmen, das gleicht erst die Überblendung über eine volle Länge aus.
    const seg = StemSeparation.defaultSegment;
    const n = seg * 2 + 777;
    final l = Float32List.fromList(List.generate(n, (i) => 0.3 * math.sin(i * 0.02) + 0.05 * math.sin(i * 1.3)));
    final r = Float32List.fromList(List.generate(n, (i) => 0.2 * math.sin(i * 0.031 + 1)));
    var runs = 0;
    final sep = StemSeparation(
      segment: seg,
      run: (mix, mag, use) {
        runs++;
        // Alles ins Schlagzeug: Spektrum unverändert, Zeit-Zweig leer.
        final spec = Float32List(4 * mag.length)..setRange(0, mag.length, mag);
        use(spec, Float32List(8 * seg));
      },
    );
    final dl = <double>[], dr = <double>[], rl = <double>[], rr = <double>[];
    final steps = <int>[];
    final ok = await sep.separate(
      l,
      r,
      (a, b, c, d) {
        dl.addAll(a);
        dr.addAll(b);
        rl.addAll(c);
        rr.addAll(d);
      },
      progress: (done, total) => steps.add(done),
    );
    expect(ok, isTrue);
    expect(runs, sep.chunksFor(n));
    expect(steps.last, sep.chunksFor(n));
    expect(dl.length, n);
    // Ohne Anfang und Ende des Lieds (dort fehlen dem Modell Rahmen).
    var err = 0.0, rest = 0.0;
    for (var i = 4096; i < n - 4096; i++) {
      err = math.max(err, (dl[i] - l[i]).abs());
      err = math.max(err, (dr[i] - r[i]).abs());
      rest = math.max(rest, rl[i].abs());
    }
    expect(err, lessThan(1e-3));
    // Der Rest ist leer (bis auf den Mittelwert des Lieds).
    expect(rest, lessThan(0.01));
  });

  test('Abbrechen zwischen den Stücken', () async {
    const seg = 4096 + 100;
    final l = Float32List(seg * 4), r = Float32List(seg * 4);
    var runs = 0;
    final sep = StemSeparation(
      segment: seg,
      run: (mix, mag, use) {
        runs++;
        use(Float32List(4 * mag.length), Float32List(8 * seg));
      },
    );
    final ok = await sep.separate(l, r, (a, b, c, d) {}, cancelled: () => runs >= 2);
    expect(ok, isFalse);
    expect(runs, 2);
  });

  test('Abtastrate 48 → 44,1 kHz: Ton bleibt gleich hoch und gleich lang', () {
    const from = 48000, to = 44100;
    final x = Float32List.fromList(List.generate(from, (i) => math.sin(2 * math.pi * 440 * i / from)));
    final y = resample(x, from, to);
    expect(y.length, to);
    var err = 0.0;
    for (var i = 200; i < to - 200; i++) {
      err = math.max(err, (y[i] - math.sin(2 * math.pi * 440 * i / to)).abs());
    }
    expect(err, lessThan(1e-3));
  });

  test('WAV schreiben: Kopf und Länge stimmen', () {
    final dir = Directory.systemTemp.createTempSync('volti_wav');
    final w = WavWriter('${dir.path}/a.wav');
    w.add(Float32List.fromList([0.5, -2]), Float32List.fromList([0, 1]));
    w.add(Float32List.fromList([0.25]), Float32List.fromList([-0.25]));
    w.close();
    final b = File('${dir.path}/a.wav').readAsBytesSync();
    expect(b.length, 44 + 3 * 4);
    final d = ByteData.sublistView(b);
    expect(String.fromCharCodes(b.sublist(0, 4)), 'RIFF');
    expect(d.getUint32(40, Endian.little), 12);
    expect(d.getInt16(44, Endian.little), 16384);
    expect(d.getInt16(48, Endian.little), -32767, reason: 'zu laut wird begrenzt');
    dir.deleteSync(recursive: true);
  });
}
