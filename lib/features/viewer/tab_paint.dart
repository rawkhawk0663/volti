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
  });

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
  return math.max(w, twoDigits ? 2.3 : 1.6);
}

TabLayout layoutTab(TabBlock t, Size page) {
  final gap = t.gap * page.width;
  final origin = Offset(t.x * page.width, t.y * page.height);
  final width = math.max(t.width * page.width, gap * (_clef + _tail + 2));
  final natural = [for (final b in t.beats) _naturalWidth(b) * gap];
  final sum = natural.fold(0.0, (a, b) => a + b);
  final room = width - gap * (_clef + _tail);
  // Zu viel für die Breite: alles gleichmässig enger (nie breiter).
  final scale = sum > room && sum > 0 ? math.max(0.35, room / sum) : 1.0;
  final xs = <double>[], widths = <double>[];
  var x = origin.dx + gap * _clef;
  for (final w in natural) {
    final s = w * scale;
    xs.add(x + s / 2);
    widths.add(s);
    x += s;
  }
  xs.add(x + gap * 1.1);
  widths.add(gap * 2.2);
  return TabLayout(
    origin: origin,
    gap: gap,
    width: width,
    xs: xs,
    slotWidths: widths,
    endX: math.max(origin.dx + width, x + gap * _tail),
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
    final r = Rect.fromLTRB(l.origin.dx - g * 0.6, l.top - g * 1.0, l.endX + g * 0.6, l.stemBottom + g * 0.8);
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
      final y = b.value == 1 ? l.stemTop + g * 0.6 : l.stemBottom - g * 0.25;
      canvas.drawCircle(Offset(cx + g * 0.5, y), g * 0.17, Paint()..color = color);
    }
  }

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
