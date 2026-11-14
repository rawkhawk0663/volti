import 'dart:math' as math;
import 'dart:typed_data';

/// Tonhöhen-Erkennung und Ton-Erzeugung für Stimmgerät und Stimmton.
/// Reine Rechnerei ohne Oberfläche (gut zu prüfen).

/// Notennamen (Index 0 = C). Deutsch: B = B♭, H = B.
const _namesDe = ['C', 'C♯', 'D', 'E♭', 'E', 'F', 'F♯', 'G', 'A♭', 'A', 'B', 'H'];
const _namesEn = ['C', 'C♯', 'D', 'E♭', 'E', 'F', 'F♯', 'G', 'A♭', 'A', 'B♭', 'B'];

/// Name der Note [midi] (60 = C4), ohne Oktave.
String noteName(int midi, {required bool english}) => (english ? _namesEn : _namesDe)[midi % 12];

/// Oktave der Note [midi] (wissenschaftlich: 60 = C4, 69 = A4).
int noteOctave(int midi) => midi ~/ 12 - 1;

/// Frequenz der Note [midi] bei Kammerton [a4] Hz.
double noteFrequency(int midi, {double a4 = 440}) => a4 * math.pow(2, (midi - 69) / 12).toDouble();

/// Nächste Note zu [hz] und Abweichung in Cent (−50..+50).
({int midi, double cents}) nearestNote(double hz, {double a4 = 440}) {
  final exact = 69 + 12 * math.log(hz / a4) / math.ln2;
  final midi = exact.round();
  return (midi: midi, cents: (exact - midi) * 100);
}

/// Grundfrequenz eines Ausschnitts [x] (Abtastrate [rate]) nach dem
/// YIN-Verfahren (de Cheveigné & Kawahara 2002). null = kein klarer Ton
/// (zu leise oder Geräusch).
///
/// Sucht zwischen [minHz] und [maxHz]. Für die Gitarre reichen 60..1400 Hz
/// (tiefes E = 82 Hz, auch Drop-D und Bass-Saiten über die Obertöne).
double? detectPitch(
  Float32List x,
  int rate, {
  double minHz = 60,
  double maxHz = 1400,
  double threshold = 0.12,
  double minRms = 0.004,
}) {
  final maxLag = (rate / minHz).ceil();
  final minLag = math.max(2, (rate / maxHz).floor());
  final window = x.length - maxLag;
  if (window < maxLag) return null;

  // Zu leise: nichts erkennen (sonst springt die Anzeige beim Rauschen).
  var sum = 0.0;
  for (var i = 0; i < x.length; i++) {
    sum += x[i] * x[i];
  }
  if (math.sqrt(sum / x.length) < minRms) return null;

  // Differenzfunktion d(τ) und ihre normierte Fassung d'(τ).
  final d = Float64List(maxLag + 1);
  for (var tau = 1; tau <= maxLag; tau++) {
    var s = 0.0;
    for (var j = 0; j < window; j++) {
      final diff = x[j] - x[j + tau];
      s += diff * diff;
    }
    d[tau] = s;
  }
  final cmnd = Float64List(maxLag + 1)..[0] = 1;
  var running = 0.0;
  for (var tau = 1; tau <= maxLag; tau++) {
    running += d[tau];
    cmnd[tau] = running == 0 ? 1 : d[tau] * tau / running;
  }

  // Erstes Tal unter der Schwelle (sonst das tiefste überhaupt, falls klar genug).
  var best = -1;
  for (var tau = minLag; tau <= maxLag; tau++) {
    if (cmnd[tau] < threshold) {
      while (tau + 1 <= maxLag && cmnd[tau + 1] < cmnd[tau]) {
        tau++;
      }
      best = tau;
      break;
    }
  }
  if (best < 0) {
    var minVal = double.infinity;
    for (var tau = minLag; tau <= maxLag; tau++) {
      if (cmnd[tau] < minVal) {
        minVal = cmnd[tau];
        best = tau;
      }
    }
    if (minVal > 0.3) return null;
  }

  // Feiner zwischen zwei Abtastpunkten (Parabel durch die Nachbarn).
  var lag = best.toDouble();
  if (best > 1 && best < maxLag) {
    // Auf der rohen Differenzfunktion ist die Parabel genauer als auf der normierten.
    final a = d[best - 1], b = d[best], c = d[best + 1];
    final denom = a - 2 * b + c;
    if (denom.abs() > 1e-12) lag = best + 0.5 * (a - c) / denom;
  }
  return rate / lag;
}

/// Glättet die erkannten Töne: Median der letzten paar Werte, damit die
/// Nadel ruhig steht. Springt der Ton (anderer Ton gespielt), gilt sofort
/// der neue.
class PitchSmoother {
  PitchSmoother({this.size = 5});
  final int size;
  final List<double> _recent = [];

  double? add(double? hz) {
    if (hz == null) {
      _recent.clear();
      return null;
    }
    if (_recent.isNotEmpty) {
      final last = _recent.last;
      // Mehr als ein Halbton daneben: neuer Ton.
      if ((12 * math.log(hz / last) / math.ln2).abs() > 0.8) _recent.clear();
    }
    _recent.add(hz);
    if (_recent.length > size) _recent.removeAt(0);
    final sorted = [..._recent]..sort();
    return sorted[sorted.length ~/ 2];
  }

  void reset() => _recent.clear();
}

/// Klang des Stimmtons.
enum PipeSound { soft, guitar }

/// Ein Stimmton als WAV (16 Bit, mono, [rate] Hz).
///
/// * [PipeSound.soft]: weicher Dauerton (Grundton mit leisen Obertönen).
///   Die Länge ist eine ganze Zahl von Schwingungen (rund eine Sekunde),
///   damit er sich ohne Knacken als Schleife wiederholen lässt.
/// * [PipeSound.guitar]: gezupfte Saite (Karplus-Strong), klingt aus.
Uint8List buildPipeTone(double hz, PipeSound sound, {int rate = 44100}) {
  final Float64List samples;
  switch (sound) {
    case PipeSound.soft:
      final periods = math.max(1, hz.round());
      final n = (periods * rate / hz).round();
      // Genau so viele Schwingungen, dass die Schleife nahtlos ist.
      final f = periods * rate / n;
      samples = Float64List(n);
      for (var i = 0; i < n; i++) {
        final t = i / rate;
        samples[i] =
            0.5 *
            (0.78 * math.sin(2 * math.pi * f * t) +
                0.16 * math.sin(2 * math.pi * 2 * f * t) +
                0.06 * math.sin(2 * math.pi * 3 * f * t));
      }
    case PipeSound.guitar:
      const seconds = 4.0;
      final n = (seconds * rate).round();
      samples = Float64List(n);
      // Verzögerungslinie mit Bruchteil (Allpass), damit der Ton genau stimmt.
      final period = rate / hz;
      // Die Schleife verzögert um len − ½ (Mittelwert aus zwei Nachbarn)
      // plus den Bruchteil aus dem Allpass.
      var len = (period + 0.5).floor();
      var frac = period + 0.5 - len;
      // Ein Allpass mit Bruchteil nahe 0 wird instabil: dann eine Stelle kürzer.
      if (frac < 0.1) {
        len--;
        frac++;
      }
      final coeff = (1 - frac) / (1 + frac);
      final buf = Float64List(len);
      final rnd = math.Random(7);
      // Anschlag: Rauschen, leicht geglättet (weicher, wie mit dem Daumen).
      var prev = 0.0;
      for (var i = 0; i < len; i++) {
        final r = rnd.nextDouble() * 2 - 1;
        prev = 0.5 * r + 0.5 * prev;
        buf[i] = prev;
      }
      var idx = 0, apIn = 0.0, apOut = 0.0;
      const damping = 0.996;
      for (var i = 0; i < n; i++) {
        final cur = buf[idx];
        final next = buf[(idx + 1) % len];
        final avg = damping * 0.5 * (cur + next);
        // Allpass für den Bruchteil der Periode.
        final out = coeff * avg + apIn - coeff * apOut;
        apIn = avg;
        apOut = out;
        buf[idx] = out;
        idx = (idx + 1) % len;
        samples[i] = 0.9 * cur;
      }
      // Ende sanft ausblenden.
      final fade = (0.3 * rate).round();
      for (var i = 0; i < fade; i++) {
        samples[n - 1 - i] *= i / fade;
      }
  }
  return _wav(samples, rate);
}

Uint8List _wav(Float64List samples, int rate) {
  final total = samples.length;
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
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, total * 2, Endian.little);
  for (var i = 0; i < total; i++) {
    data.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}
