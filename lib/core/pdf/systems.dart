import 'dart:math' as math;

/// Ein waagrechter Streifen einer Seite (normiert, 0..1), z. B. ein
/// Notensystem.
typedef Band = ({double top, double bottom});

/// Findet die Notenzeilen (Systeme) einer Seite anhand der weissen Lücken
/// dazwischen. [rgba]: Bildpunkte, 4 Byte pro Punkt.
///
/// * Eine Zeile mit genug dunklen Punkten gehört zum Inhalt.
/// * Inhalt, der durch eine genügend hohe weisse Lücke getrennt ist, wird zu
///   eigenen Streifen. Kleinere Lücken (zwischen Notenlinien und Liedtext,
///   über Hälsen …) bleiben im selben Streifen.
/// * Winzige Streifen (Staub, Seitenzahl) fallen weg.
/// * Jeder Streifen bekommt etwas Rand (höchstens die halbe Lücke).
List<Band> findSystems(List<int> rgba, int width, int height, {int threshold = 200, double minGap = 0.012}) {
  if (width <= 0 || height <= 0) return const [];
  return _byStaffLines(rgba, width, height, threshold) ?? _byGaps(rgba, width, height, threshold, minGap);
}

/// Über die Notenlinien: Fünf (bei Tabulatur sechs) lange waagrechte Linien
/// in gleichem Abstand bilden ein Notensystem. Hängen zwei Systeme mit
/// durchgehenden Taktstrichen zusammen (Klavier, Ensemble), bleiben sie ein
/// Streifen. Geschnitten wird zwischen den Systemen an der hellsten Zeile –
/// so werden keine Noten zerschnitten, auch wenn wenig Platz ist.
List<Band>? _byStaffLines(List<int> rgba, int width, int height, int threshold) {
  bool isDark(int x, int y) {
    final i = (y * width + x) * 4;
    return rgba[i] < threshold || rgba[i + 1] < threshold || rgba[i + 2] < threshold;
  }

  final counts = List<int>.filled(height, 0);
  for (var y = 0; y < height; y++) {
    var n = 0;
    for (var x = 0; x < width; x++) {
      if (isDark(x, y)) n++;
    }
    counts[y] = n;
  }
  // Notenlinien: Zeilen, die über fast die halbe Breite dunkel sind.
  final lines = <double>[];
  int? from;
  for (var y = 0; y <= height; y++) {
    final on = y < height && counts[y] >= width * 0.45;
    if (on) {
      from ??= y;
    } else if (from != null) {
      lines.add((from + y - 1) / 2);
      from = null;
    }
  }
  if (lines.length < 8) return null;
  final diffs = [for (var i = 1; i < lines.length; i++) lines[i] - lines[i - 1]]..sort();
  final space = diffs[diffs.length ~/ 3]; // typischer Linienabstand (eher die kleinen)
  // Linien zu Systemen gruppieren
  final staves = <(double, double)>[];
  var top = lines.first, last = lines.first, n = 1;
  for (var i = 1; i < lines.length; i++) {
    if (lines[i] - last <= space * 1.6) {
      last = lines[i];
      n++;
    } else {
      if (n >= 4) staves.add((top, last));
      top = last = lines[i];
      n = 1;
    }
  }
  if (n >= 4) staves.add((top, last));
  if (staves.length < 2) return null;

  // Durchgehende Taktstriche verbinden Systeme zu einem Streifen.
  bool connected((double, double) a, (double, double) b) {
    final y0 = a.$2.ceil() + 1, y1 = b.$1.floor() - 1;
    if (y1 <= y0) return true;
    var columns = 0;
    for (var x = 0; x < width; x++) {
      var dark = 0;
      for (var y = y0; y <= y1; y++) {
        if (isDark(x, y)) dark++;
      }
      if (dark >= (y1 - y0 + 1) * 0.95) columns++;
      if (columns >= 3) return true;
    }
    return false;
  }

  final groups = <(double, double)>[staves.first];
  for (var i = 1; i < staves.length; i++) {
    if (connected(groups.last, staves[i])) {
      groups[groups.length - 1] = (groups.last.$1, staves[i].$2);
    } else {
      groups.add(staves[i]);
    }
  }
  // Schnitte an der hellsten Zeile zwischen den Gruppen
  int lightest(int a, int b) {
    var best = a, bestN = 1 << 30;
    final mid = (a + b) / 2;
    for (var y = a; y <= b; y++) {
      final c = counts[y];
      if (c < bestN || (c == bestN && (y - mid).abs() < (best - mid).abs())) {
        best = y;
        bestN = c;
      }
    }
    return best;
  }

  var contentTop = 0, contentBottom = height - 1;
  while (contentTop < height && counts[contentTop] < 2) {
    contentTop++;
  }
  while (contentBottom > 0 && counts[contentBottom] < 2) {
    contentBottom--;
  }
  final cuts = <int>[math.max(0, contentTop - 4)];
  for (var i = 1; i < groups.length; i++) {
    cuts.add(lightest(groups[i - 1].$2.ceil() + 2, groups[i].$1.floor() - 2));
  }
  cuts.add(math.min(height, contentBottom + 5));
  // Was über dem ersten System steht (Titel), bekommt einen eigenen Streifen,
  // wenn es durch eine Lücke getrennt ist.
  final bands = <Band>[];
  final firstTop = groups.first.$1.floor();
  final above = _byGaps(rgba, width, firstTop, threshold, 0.02);
  if (above.length > 1) {
    final titleBottom = (above[above.length - 2].bottom * firstTop).round();
    bands.add((top: cuts.first / height, bottom: titleBottom / height));
    cuts[0] = titleBottom;
  }
  for (var i = 0; i + 1 < cuts.length; i++) {
    if (cuts[i + 1] - cuts[i] > 4) bands.add((top: cuts[i] / height, bottom: cuts[i + 1] / height));
  }
  return bands;
}

/// Über weisse Lücken zwischen den Zeilen (für Seiten ohne erkennbare
/// Notenlinien, z. B. Liedtexte mit Akkorden).
List<Band> _byGaps(List<int> rgba, int width, int height, int threshold, double minGap) {
  if (height <= 0) return const [];
  final minDark = math.max(2, (width * 0.004).ceil());
  final dark = List<bool>.filled(height, false);
  for (var y = 0; y < height; y++) {
    var n = 0;
    final row = y * width * 4;
    for (var x = 0; x < width; x++) {
      final i = row + x * 4;
      if (rgba[i] < threshold || rgba[i + 1] < threshold || rgba[i + 2] < threshold) {
        if (++n >= minDark) break;
      }
    }
    dark[y] = n >= minDark;
  }
  final gap = math.max(4, (height * minGap).round());
  final raw = <(int, int)>[];
  int? start;
  var lastDark = -1;
  for (var y = 0; y < height; y++) {
    if (!dark[y]) continue;
    if (start == null) {
      start = y;
    } else if (y - lastDark > gap) {
      raw.add((start, lastDark));
      start = y;
    }
    lastDark = y;
  }
  if (start != null) raw.add((start, lastDark));
  // Staub und Seitenzahlen weglassen
  final minHeight = math.max(3, (height * 0.012).round());
  final kept = [
    for (final b in raw)
      if (b.$2 - b.$1 + 1 >= minHeight) b,
  ];
  return [
    for (var i = 0; i < kept.length; i++)
      () {
        final (a, b) = kept[i];
        final above = i == 0 ? a : (a - kept[i - 1].$2) / 2;
        final below = i == kept.length - 1 ? height - 1 - b : (kept[i + 1].$1 - b) / 2;
        final pad = height * 0.012;
        final top = math.max(0.0, a - math.min(pad, above));
        final bottom = math.min(height.toDouble(), b + 1 + math.min(pad, below));
        return (top: top / height, bottom: bottom / height);
      }(),
  ];
}
