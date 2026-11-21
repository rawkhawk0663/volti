import 'dart:math' as math;
import 'dart:typed_data';

import 'stft.dart';

/// Rechnet ein Stück durch das Trenn-Modell: [mix] ist [2][segment]
/// (links, rechts), [mag] das Spektrum dazu. [use] bekommt die Ausgaben
/// `spec` [4 Spuren][4][bins][frames] und `wave` [4 Spuren][2][segment]
/// (nur während des Aufrufs gültig).
typedef StemModelRun =
    void Function(Float32List mix, Float32List mag, void Function(Float32List spec, Float32List wave) use);

/// Gibt fertige Werte der vier Spuren weiter: [channels] hat 8 Listen
/// (Spur s, Kanal c an Stelle 2·s + c), alle gleich lang.
typedef StemSink = void Function(List<Float32List> channels);

/// Die Spuren in der Reihenfolge des Modells.
enum Stem { drums, bass, other, vocals }

/// Trennt ein Lied in Schlagzeug, Bass, Instrumente (Gitarre, Keys …) und
/// Gesang.
///
/// Ablauf wie beim Trenn-Modell selbst: Das ganze Lied wird normiert, in
/// Stücke von 7,8 s mit 25 % Überlappung zerlegt (das letzte wird mit echtem
/// Ton davor aufgefüllt), jedes Stück einzeln gerechnet und weich
/// überblendet. Fertige Werte gehen laufend an [sink], so braucht es nie das
/// ganze Ergebnis im Speicher.
class StemSeparation {
  StemSeparation({required this.run, this.segment = defaultSegment});

  /// Stücklänge des Modells (7,8 s bei 44,1 kHz).
  static const defaultSegment = 343980;
  static const sampleRate = 44100;

  final StemModelRun run;
  final int segment;

  int get stride => (segment * 0.75).toInt();

  /// Anzahl Stücke für ein Lied mit [n] Werten je Kanal.
  int chunksFor(int n) => n <= 0 ? 0 : (n + stride - 1) ~/ stride;

  /// Trennt [left]/[right] (44,1 kHz). [progress] bekommt erledigte und
  /// gesamte Stücke; [cancelled] wird zwischen den Stücken gefragt (true =
  /// abbrechen, dann gibt es false zurück).
  Future<bool> separate(
    Float32List left,
    Float32List right,
    StemSink sink, {
    void Function(int done, int total)? progress,
    bool Function()? cancelled,
    Future<void> Function()? breathe,
  }) async {
    final n = left.length;
    final total = chunksFor(n);
    if (total == 0) return true;

    // Ganzes Lied normieren (Mittelwert und Streuung der Mono-Summe).
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      sum += (left[i] + right[i]) * 0.5;
    }
    final mean = sum / n;
    var sq = 0.0;
    for (var i = 0; i < n; i++) {
      final d = (left[i] + right[i]) * 0.5 - mean;
      sq += d * d;
    }
    final std = math.max(math.sqrt(sq / math.max(1, n - 1)), 1e-8);

    final seg = segment;
    final half = seg ~/ 2;
    final weight = Float64List(seg);
    for (var i = 0; i < seg; i++) {
      weight[i] = (i < half ? i + 1 : seg - i) / half;
    }
    final spectrum = DemucsSpectrum(seg);
    final mixL = Float32List(seg), mixR = Float32List(seg);
    final mix = Float32List(2 * seg);

    // Laufende Summen ab [base] (eine Stücklänge), je Spur und Kanal.
    const channels = 2 * 4;
    final acc = List.generate(channels, (_) => Float64List(seg));
    final wsum = Float64List(seg);
    var base = 0;
    final out = List.generate(channels, (_) => Float64List(seg));

    for (var k = 0; k < total; k++) {
      if (cancelled?.call() ?? false) return false;
      final offset = k * stride;
      final len = math.min(seg, n - offset);
      // Kürzeres Stück: mit echtem Ton davor und danach auf volle Länge,
      // die Mitte zählt.
      final delta = seg - len;
      final start = offset - delta ~/ 2;
      for (var i = 0; i < seg; i++) {
        final j = start + i;
        final inside = j >= 0 && j < n;
        mixL[i] = inside ? (left[j] - mean) / std : 0;
        mixR[i] = inside ? (right[j] - mean) / std : 0;
      }
      mix.setRange(0, seg, mixL);
      mix.setRange(seg, 2 * seg, mixR);
      final mag = spectrum.forward(mixL, mixR);

      run(mix, mag, (spec, wave) {
        final specStem = 4 * DemucsSpectrum.bins * spectrum.frames;
        for (var st = 0; st < 4; st++) {
          final l = out[2 * st], r = out[2 * st + 1];
          l.fillRange(0, seg, 0);
          r.fillRange(0, seg, 0);
          spectrum.inverse(spec, st * specStem, l, r);
          final wl = 2 * st * seg, wr = (2 * st + 1) * seg;
          for (var i = 0; i < seg; i++) {
            l[i] += wave[wl + i];
            r[i] += wave[wr + i];
          }
        }
      });

      // Mitte des Stücks gewichtet aufaddieren.
      final trim = delta ~/ 2;
      final at = offset - base;
      for (var c = 0; c < channels; c++) {
        final a = acc[c], o = out[c];
        for (var i = 0; i < len; i++) {
          a[at + i] += o[trim + i] * weight[i];
        }
      }
      for (var i = 0; i < len; i++) {
        wsum[at + i] += weight[i];
      }

      // Fertig ist alles vor dem nächsten Stück.
      final next = offset + stride;
      final upto = (next < n ? next : n) - base;
      final done = List.generate(channels, (_) => Float32List(upto));
      for (var c = 0; c < channels; c++) {
        final a = acc[c], d = done[c];
        for (var i = 0; i < upto; i++) {
          final w = wsum[i];
          d[i] = (w > 0 ? a[i] / w : 0) * std + mean;
        }
      }
      sink(done);
      if (next < n) {
        for (final a in [...acc, wsum]) {
          a.setRange(0, seg - upto, a, upto);
          a.fillRange(seg - upto, seg, 0);
        }
        base += upto;
      }
      progress?.call(k + 1, total);
      if (breathe != null) await breathe();
    }
    return true;
  }
}
