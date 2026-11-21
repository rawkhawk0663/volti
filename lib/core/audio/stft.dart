import 'dart:math' as math;
import 'dart:typed_data';

/// Schnelle Fourier-Transformation (komplex, Zweierpotenz, an Ort und Stelle).
class Fft {
  Fft(this.n)
    : assert(n > 1 && (n & (n - 1)) == 0, 'Zweierpotenz'),
      _cos = Float64List(n ~/ 2),
      _sin = Float64List(n ~/ 2),
      _rev = Int32List(n) {
    for (var i = 0; i < n ~/ 2; i++) {
      _cos[i] = math.cos(2 * math.pi * i / n);
      _sin[i] = math.sin(2 * math.pi * i / n);
    }
    var bits = 0;
    while ((1 << bits) < n) {
      bits++;
    }
    for (var i = 0; i < n; i++) {
      var r = 0;
      for (var b = 0; b < bits; b++) {
        if (i & (1 << b) != 0) r |= 1 << (bits - 1 - b);
      }
      _rev[i] = r;
    }
  }

  final int n;
  final Float64List _cos, _sin;
  final Int32List _rev;

  /// Vorwärts (e^−i…) bzw. mit [inverse] rückwärts (ohne 1/n).
  void transform(Float64List re, Float64List im, {bool inverse = false}) {
    for (var i = 0; i < n; i++) {
      final j = _rev[i];
      if (j > i) {
        final tr = re[i], ti = im[i];
        re[i] = re[j];
        im[i] = im[j];
        re[j] = tr;
        im[j] = ti;
      }
    }
    final sign = inverse ? 1.0 : -1.0;
    for (var size = 2; size <= n; size <<= 1) {
      final half = size >> 1;
      final step = n ~/ size;
      for (var start = 0; start < n; start += size) {
        var k = 0;
        for (var j = start; j < start + half; j++) {
          final wr = _cos[k], wi = sign * _sin[k];
          final l = j + half;
          final xr = re[l] * wr - im[l] * wi;
          final xi = re[l] * wi + im[l] * wr;
          re[l] = re[j] - xr;
          im[l] = im[j] - xi;
          re[j] += xr;
          im[j] += xi;
          k += step;
        }
      }
    }
  }
}

/// Spektral-Umrechnung genau wie im Trenn-Modell (htdemucs): Fenster 4096,
/// Schritt 1024, Hann-Fenster, normiert, Ränder gespiegelt.
///
/// Ein Stück hat [length] Werte je Kanal (stereo). Das Spektrum hat
/// [bins] Frequenzen × [frames] Zeitschritte.
class DemucsSpectrum {
  DemucsSpectrum(this.length)
    : frames = (length + hop - 1) ~/ hop,
      _fft = Fft(nfft),
      _window = Float64List(nfft) {
    for (var i = 0; i < nfft; i++) {
      _window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / nfft);
    }
    // Hüllkurve für die Rückrechnung: Summe der quadrierten Fenster aller
    // Rahmen (auch der leeren am Rand), wie bei torch.istft.
    final total = frames + 4; // 2 leere Rahmen vorne und hinten
    _envelope = Float64List((total - 1) * hop + nfft);
    for (var f = 0; f < total; f++) {
      for (var i = 0; i < nfft; i++) {
        _envelope[f * hop + i] += _window[i] * _window[i];
      }
    }
  }

  static const nfft = 4096, hop = 1024, bins = nfft ~/ 2;

  /// Rand, den das Modell vor der Umrechnung spiegelt.
  static const _pad = hop ~/ 2 * 3;

  final int length;
  final int frames;
  final Fft _fft;
  final Float64List _window;
  late final Float64List _envelope;

  final _re = Float64List(nfft), _im = Float64List(nfft);

  /// Gespiegelter Rand (wie `F.pad(mode='reflect')`).
  static int _reflect(int i, int n) {
    while (i < 0 || i >= n) {
      if (i < 0) i = -i;
      if (i >= n) i = 2 * (n - 1) - i;
    }
    return i;
  }

  /// Spektrum beider Kanäle als Eingabe des Modells: [4][bins][frames]
  /// (links real, links imaginär, rechts real, rechts imaginär).
  Float32List forward(Float32List left, Float32List right) {
    final out = Float32List(4 * bins * frames);
    // 1. Spiegeln wie das Modell (_spec), 2. Spiegeln für die Fenster-Mitte.
    final padded = frames * hop + 2 * _pad; // Länge nach Schritt 1
    final scale = 1 / math.sqrt(nfft);
    for (var t = 0; t < frames; t++) {
      // Rahmen t+2 (die ersten beiden schneidet das Modell weg).
      final start = (t + 2) * hop - nfft ~/ 2;
      for (var i = 0; i < nfft; i++) {
        final p = _reflect(start + i, padded); // Index nach Schritt 1
        final s = _reflect(p - _pad, length); // Index im Stück
        final w = _window[i];
        _re[i] = left[s] * w;
        _im[i] = right[s] * w;
      }
      _fft.transform(_re, _im);
      // Zwei reelle Kanäle aus einer komplexen Transformation trennen.
      for (var k = 0; k < bins; k++) {
        final m = (nfft - k) & (nfft - 1);
        final ar = _re[k], ai = _im[k], br = _re[m], bi = _im[m];
        final lr = 0.5 * (ar + br), li = 0.5 * (ai - bi);
        final rr = 0.5 * (ai + bi), ri = -0.5 * (ar - br);
        final at = k * frames + t;
        out[at] = lr * scale;
        out[bins * frames + at] = li * scale;
        out[2 * bins * frames + at] = rr * scale;
        out[3 * bins * frames + at] = ri * scale;
      }
    }
    return out;
  }

  /// Zurück in Töne (wie `_ispec` des Modells). [spec] ist [4][bins][frames]
  /// ab [offset]; das Ergebnis wird zu [left]/[right] addiert.
  void inverse(Float32List spec, int offset, Float64List left, Float64List right) {
    final total = frames + 4;
    final ola = Float64List((total - 1) * hop + nfft);
    final olaR = Float64List(ola.length);
    final plane = bins * frames;
    final scale = math.sqrt(nfft) / nfft; // normiert, und 1/n der Rücktransformation
    for (var t = 0; t < frames; t++) {
      // Spektrum (L + i·R) zusammensetzen, Nyquist-Frequenz ist 0.
      for (var k = 0; k < bins; k++) {
        final at = offset + k * frames + t;
        var lr = spec[at], li = spec[plane + at];
        var rr = spec[2 * plane + at], ri = spec[3 * plane + at];
        if (k == 0) li = ri = 0;
        _re[k] = lr - ri;
        _im[k] = li + rr;
        if (k > 0) {
          _re[nfft - k] = lr + ri;
          _im[nfft - k] = -li + rr;
        }
      }
      _re[bins] = 0;
      _im[bins] = 0;
      _fft.transform(_re, _im, inverse: true);
      final base = (t + 2) * hop;
      for (var i = 0; i < nfft; i++) {
        final w = _window[i] * scale;
        ola[base + i] += _re[i] * w;
        olaR[base + i] += _im[i] * w;
      }
    }
    final from = nfft ~/ 2 + _pad;
    for (var i = 0; i < length; i++) {
      final e = _envelope[from + i];
      if (e > 1e-11) {
        left[i] += ola[from + i] / e;
        right[i] += olaR[from + i] / e;
      }
    }
  }
}
