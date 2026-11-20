import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../core/ink/tab_block.dart';

/// Lage einer Tabulatur auf der Seite (in Bildpunkten).
class TabLayout {
  TabLayout({
    required this.origin,
    required this.gap,
    required this.width,
    required this.xs,
    required this.slotWidths,
    required this.endX,
    required this.contentStart,
    required this.contentEnd,
  });

  /// Schreibbereich (gleich nach „TAB“ bis zum rechten Ende): Darin liegen
  /// verschobene Taktstriche ([TabBeat.at] 0 … 1).
  final double contentStart, contentEnd;

  /// Lage im Schreibbereich (0 … 1) zur Stelle [dx].
  double fractionAt(double dx) => ((dx - contentStart) / (contentEnd - contentStart)).clamp(0.0, 1.0);

  /// Linke obere Ecke (oberste Linie).
  final Offset origin;

  /// Abstand der Linien.
  final double gap;
  final double width;

  /// Mitte jedes Eintrags (Schlag oder Taktstrich); dazu als letzter Wert der
  /// freie Platz hinter dem letzten Eintrag (für den Cursor).
  final List<double> xs;

  /// Breite jedes Eintrags (wie [xs]).
  final List<double> slotWidths;

  /// Ende der Linien.
  final double endX;

  double get top => origin.dy;
  double get bottom => origin.dy + gap * (TabBlock.strings - 1);
  double lineY(int string) => origin.dy + gap * string;

  /// Hälse: von hier …
  double get stemTop => bottom + gap * 0.8;

  /// … bis hier (dort liegen auch die Balken).
  double get stemBottom => bottom + gap * 3.2;

  /// Ganze Fläche inkl. Rhythmus darunter (zum Antippen).
  Rect get bounds => Rect.fromLTRB(origin.dx, top - gap * 1.2, endX, stemBottom + gap * 0.6);

  /// Nächster Platz (Eintrag oder freier Platz am Ende) zu [dx].
  int slotAt(double dx) {
    var best = 0;
    var dist = double.infinity;
    for (var i = 0; i < xs.length; i++) {
      final d = (xs[i] - dx).abs();
      if (d < dist) {
        dist = d;
        best = i;
      }
    }
    return best;
  }

  /// Nächste Saite zu [dy].
  int stringAt(double dy) => ((dy - top) / gap).round().clamp(0, TabBlock.strings - 1);
}

/// Breite des „TAB“-Zeichens am Anfang (in Linienabständen).
const _clef = 3.0;

/// Breite der Taktart (in Linienabständen).
double _meterWidth(String meter) {
  final digits = meter.split('/').map((p) => p.length).fold(1, math.max);
  return 1.4 + digits * 2.0;
}

/// Ziffern der Taktart in der Notenschrift Bravura.
String _meterDigits(String n) => String.fromCharCodes(n.codeUnits.map((c) => 0xE080 + c - 0x30));

/// Freier Platz hinter dem letzten Eintrag (in Linienabständen).
const _tail = 2.4;

/// Natürliche Breite eines Eintrags in Linienabständen: Längere Notenwerte
/// bekommen mehr Platz, damit man den Rhythmus auch im Abstand sieht.
double _naturalWidth(TabBeat b) {
  if (b.bar) return 1.4;
  final base = switch (b.value) {
    1 => 4.4,
    2 => 3.5,
    4 => 2.8,
    8 => 2.2,
    16 => 1.9,
    _ => 1.7,
  };
  final w = base * (b.dotted ? 1.2 : 1);
  final twoDigits = b.frets.values.any((f) => f >= 10);
  // Platz für den Bending-Pfeil rechts neben der Zahl.
  final bend = b.bends.isNotEmpty ? 1.0 : 0.0;
  return math.max(w, twoDigits ? 2.3 : 1.6) + bend;
}

TabLayout layoutTab(TabBlock t, Size page) {
  final gap = t.gap * page.width;
  final origin = Offset(t.x * page.width, t.y * page.height);
  // Mit Taktart steht sie nach „TAB“ und braucht etwas mehr Platz.
  final clef = _clef + (t.measure != null ? _meterWidth(t.meter!) : 0);
  final width = math.max(t.width * page.width, gap * (clef + _tail + 2));
  final start = origin.dx + gap * clef;
  final contentEnd = origin.dx + width;

  // 1. Natürliche Lage (ohne Enge): Mitte und Breite jedes Eintrags.
  final nw = [for (final b in t.beats) _naturalWidth(b) * gap];
  final nx = <double>[];
  var x = start;
  for (final w in nw) {
    nx.add(x + w / 2);
    x += w;
  }
  final naturalEnd = x; // Ende des letzten Eintrags

  // 2. Von Hand verschobene Taktstriche sind Fixpunkte: Was dazwischen liegt,
  //    wird passend gestreckt oder gestaucht.
  final anchors = <({int index, double from, double to})>[(index: -1, from: start, to: start)];
  for (var i = 0; i < t.beats.length; i++) {
    final at = t.beats[i].at;
    if (!t.beats[i].bar || at == null) continue;
    final to = start + at * (contentEnd - start);
    // Nur in der richtigen Reihenfolge und mit etwas Platz dazwischen.
    if (to <= anchors.last.to + gap) continue;
    anchors.add((index: i, from: nx[i], to: to));
  }

  // Hinter dem letzten Fixpunkt: wie gewohnt, aber zu viel → enger (nie breiter).
  final last = anchors.last;
  final tailFrom = last.index < 0 ? start : nx[last.index] + nw[last.index] / 2;
  final tailTo = last.index < 0 ? start : last.to + nw[last.index] / 2;
  final tailRoom = contentEnd - gap * _tail - tailTo;
  final tailNatural = naturalEnd - tailFrom;
  final tailScale = tailNatural > tailRoom && tailNatural > 0 ? math.max(0.35, tailRoom / tailNatural) : 1.0;

  double map(int i, double v) {
    // Fixpunkt davor und danach suchen.
    for (var k = 0; k < anchors.length - 1; k++) {
      final a = anchors[k], b = anchors[k + 1];
      if (i > a.index && i <= b.index) {
        final f = (b.from - a.from).abs() < 1e-6 ? 1.0 : (b.to - a.to) / (b.from - a.from);
        return a.to + (v - a.from) * f;
      }
    }
    if (last.index < 0) return start + (v - start) * tailScale;
    return tailTo + (v - tailFrom) * tailScale;
  }

  double factor(int i) {
    for (var k = 0; k < anchors.length - 1; k++) {
      final a = anchors[k], b = anchors[k + 1];
      if (i > a.index && i <= b.index) {
        return (b.from - a.from).abs() < 1e-6 ? 1.0 : (b.to - a.to) / (b.from - a.from);
      }
    }
    return tailScale;
  }

  final xs = <double>[], widths = <double>[];
  for (var i = 0; i < nx.length; i++) {
    xs.add(map(i, nx[i]));
    widths.add(nw[i] * factor(i));
  }
  final endOfLast = xs.isEmpty ? start : xs.last + widths.last / 2;
  xs.add(endOfLast + gap * 1.1);
  widths.add(gap * 2.2);
  return TabLayout(
    origin: origin,
    gap: gap,
    width: width,
    xs: xs,
    slotWidths: widths,
    endX: math.max(contentEnd, endOfLast + gap * _tail),
    contentStart: start,
    contentEnd: contentEnd,
  );
}

/// Pausen-Zeichen in der Notenschrift Bravura (SMuFL).
int _restGlyph(int value) => switch (value) {
  1 => 0xE4E3,
  2 => 0xE4E4,
  4 => 0xE4E5,
  8 => 0xE4E6,
  16 => 0xE4E7,
  _ => 0xE4E8,
};

/// Wie viele Balken bzw. Fähnchen ein Notenwert hat (Achtel 1, Sechzehntel 2 …).
int _beamCount(int value) => switch (value) {
  8 => 1,
  16 => 2,
  32 => 3,
  _ => 0,
};

/// Gruppen von Schlägen, die gemeinsame Balken bekommen: Achtel und kürzer
/// innerhalb derselben Viertel eines Takts, ohne Pause dazwischen.
List<List<int>> beamGroups(List<TabBeat> beats) {
  final groups = <List<int>>[];
  var t = 0.0;
  List<int>? cur;
  int? curQuarter;
  for (var i = 0; i < beats.length; i++) {
    final b = beats[i];
    if (b.bar) {
      t = 0;
      cur = null;
      continue;
    }
    final quarter = (t / 0.25 + 1e-9).floor();
    if (!b.isRest && _beamCount(b.value) > 0) {
      if (cur != null && curQuarter == quarter) {
        cur.add(i);
      } else {
        cur = [i];
        curQuarter = quarter;
        groups.add(cur);
      }
    } else {
      cur = null;
    }
    t += b.length;
  }
  return groups;
}

TextPainter _text(String s, double size, Color color, {String family = 'VoltiSans', bool bold = false}) => TextPainter(
  text: TextSpan(
    text: s,
    style: TextStyle(
      fontFamily: family,
      fontSize: size,
      color: color,
      height: 1,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      fontVariations: [FontVariation.weight(bold ? 700 : 500)],
    ),
  ),
  textDirection: TextDirection.ltr,
)..layout();

/// Malt eine Tabulatur (Linien, Bundzahlen, Taktstriche, Pausen, Rhythmus).
void paintTabBlock(Canvas canvas, TabBlock t, Size page, {TabLayout? layout}) {
  final l = layout ?? layoutTab(t, page);
  final g = l.gap;
  final color = Color(t.color);
  final thin = Paint()
    ..color = color
    ..strokeWidth = math.max(0.7, g * 0.075);
  final stem = Paint()
    ..color = color
    ..strokeWidth = math.max(0.8, g * 0.09);

  // Hintergrund (falls gewählt) hinter allem, mit etwas Rand.
  final bg = t.background != TabBlock.noBackground ? Color(t.background) : null;
  if (bg != null) {
    // Mit Bendings ragt der Pfeil samt Stufe über die oberste Linie hinaus.
    final above = t.beats.any((b) => b.bends.isNotEmpty) ? 2.4 : 1.0;
    final r = Rect.fromLTRB(l.origin.dx - g * 0.6, l.top - g * above, l.endX + g * 0.6, l.stemBottom + g * 0.8);
    canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(g * 0.5)), Paint()..color = bg);
  }
  // Hinter Zahlen und „TAB“: der Hintergrund bzw. Weiss (die Seite).
  const white = Color(0xFFFFFFFF);
  final ground = bg != null ? Color.alphaBlend(bg, white) : white;

  // Linien und Anfangsstrich
  for (var s = 0; s < TabBlock.strings; s++) {
    canvas.drawLine(Offset(l.origin.dx, l.lineY(s)), Offset(l.endX, l.lineY(s)), thin);
  }
  canvas.drawLine(Offset(l.origin.dx, l.top), Offset(l.origin.dx, l.bottom), stem);

  // „TAB“ senkrecht am Anfang
  for (final (i, ch) in ['T', 'A', 'B'].indexed) {
    final p = _text(ch, g * 1.45, color, bold: true);
    final cy = l.top + g * (1.0 + i * 1.5);
    final at = Offset(l.origin.dx + g * 1.4 - p.width / 2, cy - p.height / 2);
    canvas.drawRect((at & p.size).inflate(g * 0.08), Paint()..color = ground);
    p.paint(canvas, at);
    p.dispose();
  }

  // Taktart nach „TAB“: Zähler oben, Nenner unten.
  if (t.measure != null) {
    final parts = t.meter!.split('/');
    final cx = l.origin.dx + g * (_clef + 0.3 + _meterWidth(t.meter!) / 2);
    for (final (i, part) in parts.indexed) {
      final p = _text(_meterDigits(part), g * 4.8, color, family: 'Bravura');
      final base = p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      // Die Ziffern sind um ihre Grundlinie herum gezeichnet.
      final cy = l.top + g * (i == 0 ? 1.25 : 3.75);
      p.paint(canvas, Offset(cx - p.width / 2, cy - base));
      p.dispose();
    }
  }

  final knockout = Paint()..color = ground;
  for (var i = 0; i < t.beats.length; i++) {
    final b = t.beats[i];
    final cx = l.xs[i];
    if (b.bar) {
      canvas.drawLine(Offset(cx, l.top), Offset(cx, l.bottom), stem);
      continue;
    }
    if (b.isRest) {
      final p = _text(String.fromCharCode(_restGlyph(b.value)), g * 4, color, family: 'Bravura');
      final base = p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      final mid = l.top + g * 2.5;
      // Ganze Pause hängt an einer Linie, die anderen sitzen in der Mitte.
      final y = b.value == 1 ? l.lineY(2) : (b.value == 2 ? l.lineY(3) : mid);
      p.paint(canvas, Offset(cx - p.width / 2, y - base));
      if (b.dotted) {
        canvas.drawCircle(Offset(cx + p.width / 2 + g * 0.35, mid - g * 0.5), g * 0.17, Paint()..color = color);
      }
      p.dispose();
      continue;
    }
    // Bundzahlen auf den Linien, mit weissem Grund (die Linie läuft nicht durch).
    for (final e in b.frets.entries) {
      final p = _text('${e.value}', g * 1.15, color);
      final cy = l.lineY(e.key);
      final r = Rect.fromCenter(center: Offset(cx, cy), width: p.width + g * 0.3, height: g * 0.95);
      canvas.drawRect(r, knockout);
      p.paint(canvas, Offset(cx - p.width / 2, cy - p.height / 2));
      // Halbe und ganze Noten: Zahl eingekreist.
      if (b.value <= 2) {
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, cy), width: math.max(p.width + g * 0.45, g * 1.05), height: g * 1.05),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = thin.strokeWidth,
        );
      }
      p.dispose();
    }
    // Hals (nicht bei ganzen Noten)
    if (b.value >= 2) canvas.drawLine(Offset(cx, l.stemTop), Offset(cx, l.stemBottom), stem);
    if (b.dotted) {
      // Oben neben dem Hals: Dort liegen nie Balken (die sind unten, bis zu
      // drei übereinander bei 32steln).
      canvas.drawCircle(Offset(cx + g * 0.5, l.stemTop + g * 0.45), g * 0.17, Paint()..color = color);
    }
  }

  _paintTechniques(canvas, t, l, color, thin.strokeWidth);

  // Balken und Fähnchen
  final beam = Paint()..color = color;
  final thick = g * 0.38, step = g * 0.6;
  void bar(double x1, double x2, int level) {
    final y = l.stemBottom - level * step;
    canvas.drawRect(Rect.fromLTRB(math.min(x1, x2), y - thick, math.max(x1, x2) + stem.strokeWidth / 2, y), beam);
  }

  for (final group in beamGroups(t.beats)) {
    if (group.length == 1) {
      // Einzeln: Fähnchen
      final i = group.single;
      final cx = l.xs[i];
      final flag = Paint()
        ..color = color
        ..strokeWidth = thick * 0.8
        ..strokeCap = StrokeCap.round;
      for (var k = 0; k < _beamCount(t.beats[i].value); k++) {
        final y = l.stemBottom - k * step;
        canvas.drawLine(Offset(cx, y), Offset(cx + g * 0.9, y - g * 0.9), flag);
      }
      continue;
    }
    bar(l.xs[group.first], l.xs[group.last], 0);
    for (var level = 1; level < 3; level++) {
      for (var n = 0; n < group.length; n++) {
        final i = group[n];
        if (_beamCount(t.beats[i].value) <= level) continue;
        final next = n + 1 < group.length ? group[n + 1] : null;
        final prev = n > 0 ? group[n - 1] : null;
        if (next != null && _beamCount(t.beats[next].value) > level) {
          bar(l.xs[i], l.xs[next], level);
        } else if (prev == null || _beamCount(t.beats[prev].value) <= level) {
          // Kein Nachbar mit so vielen Balken: kurzer Stummel.
          final dir = next != null ? 1.0 : -1.0;
          bar(l.xs[i], l.xs[i] + dir * g * 0.9, level);
        }
      }
    }
  }
}

/// Halbe Breite einer Bundzahl (für den Abstand von Slides und Bendings).
double _halfNumber(int fret, double g) => (fret >= 10 ? 1.25 : 0.65) * g * 0.5;

/// Slides (schräge Linie zur nächsten Note auf derselben Saite) und
/// Bendings (gebogener Pfeil nach oben, darüber die Stufe).
void _paintTechniques(Canvas canvas, TabBlock t, TabLayout l, Color color, double lineWidth) {
  final g = l.gap;
  final line = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = math.max(0.9, lineWidth * 1.4);
  for (var i = 0; i < t.beats.length; i++) {
    final b = t.beats[i];
    if (b.bar) continue;
    final cx = l.xs[i];
    for (final st in b.slides) {
      final fret = b.frets[st];
      if (fret == null) continue;
      final y = l.lineY(st);
      final x1 = cx + _halfNumber(fret, g) + g * 0.15;
      // Nächste Bundzahl auf dieser Saite (auch über Taktstriche hinweg).
      int? j;
      for (var k = i + 1; k < t.beats.length; k++) {
        if (!t.beats[k].bar && t.beats[k].frets.containsKey(st)) {
          j = k;
          break;
        }
      }
      if (j != null) {
        final to = t.beats[j].frets[st]!;
        final x2 = l.xs[j] - _halfNumber(to, g) - g * 0.15;
        // Aufwärts (höherer Bund) steigt die Linie, abwärts fällt sie.
        final up = to >= fret;
        final dy = g * 0.3;
        canvas.drawLine(
          Offset(x1, up ? y + dy : y - dy),
          Offset(math.max(x1 + g * 0.4, x2), up ? y - dy : y + dy),
          line,
        );
      } else {
        // Kein Ziel: kurzer Slide nach unten.
        canvas.drawLine(Offset(x1, y - g * 0.25), Offset(x1 + g * 1.0, y + g * 0.35), line);
      }
    }
    for (final e in b.bends.entries) {
      final fret = b.frets[e.key];
      if (fret == null) continue;
      final y = l.lineY(e.key);
      final x0 = cx + _halfNumber(fret, g) + g * 0.12;
      final x1 = x0 + g * 0.85;
      final top = l.top - g * 1.1;
      final path = Path()
        ..moveTo(x0, y)
        ..quadraticBezierTo(x1, y, x1, top + g * 0.45);
      canvas.drawPath(path, line);
      // Pfeilspitze nach oben
      final head = g * 0.45;
      canvas.drawPath(
        Path()
          ..moveTo(x1, top)
          ..lineTo(x1 - head * 0.5, top + head)
          ..lineTo(x1 + head * 0.5, top + head)
          ..close(),
        Paint()..color = color,
      );
      final label = TextPainter(
        text: TextSpan(
          text: bendLabel(e.value),
          style: TextStyle(fontFamily: 'VoltiSans', fontSize: g * 0.95, color: color, height: 1),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(x1 - label.width / 2, top - g * 0.1 - label.height));
      label.dispose();
    }
  }
}
