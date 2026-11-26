import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/ink/tab_block.dart';

/// Lage einer Tabulatur auf der Seite (in Bildpunkten).
class TabLayout {
  TabLayout({
    required this.origin,
    required this.gap,
    required this.width,
    required this.xs,
    required this.slotWidths,
    required this.lineXs,
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

  /// Lage des Taktstrichs selbst (wie [xs]; bei einem Taktwechsel steht der
  /// Strich links und die neue Taktart rechts davon im selben Platz).
  final List<double> lineXs;

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
  return 0.8 + digits * 1.1;
}

/// Ziffern der Taktart in der Notenschrift Bravura.
String _meterDigits(String n) => String.fromCharCodes(n.codeUnits.map((c) => 0xE080 + c - 0x30));

/// Freier Platz hinter dem letzten Eintrag (in Linienabständen).
const _tail = 2.4;

/// Natürliche Breite eines Eintrags in Linienabständen: Längere Notenwerte
/// bekommen mehr Platz, damit man den Rhythmus auch im Abstand sieht.
double _naturalWidth(TabBeat b) {
  if (b.bar) return _barWidth(b.kind) + (b.meter != null ? _meterWidth(b.meter!) + 0.3 : 0);
  final base = switch (b.value) {
    1 => 4.4,
    2 => 3.5,
    4 => 2.8,
    8 => 2.2,
    16 => 1.9,
    _ => 1.7,
  };
  final w = base * (b.dotted ? (b.doubleDot ? 1.32 : 1.2) : 1);
  final twoDigits = b.frets.values.any((f) => f >= 10);
  // Platz für den Bending-Pfeil rechts neben der Zahl.
  final bend = b.bends.isNotEmpty ? 1.0 : 0.0;
  // Platz für Slides in den Ton hinein bzw. aus ihm heraus.
  // … und für den Haltebogen von davor samt Klammern.
  // … und für Vorschlagsnoten davor.
  final slide =
      (b.slideIns.isNotEmpty ? 0.9 : 0.0) +
      (b.slideOuts.isNotEmpty ? 0.7 : 0.0) +
      (b.tieIns.isNotEmpty ? 1.2 : 0.0) +
      (b.graces.isNotEmpty ? 2.4 : 0.0) +
      // Strumming-Pfeil vor dem Schlag, Trillerbund und Klammern danach.
      (b.mark(TabMark.strum) == 1 || b.mark(TabMark.strum) == 2 ? 0.9 : 0.0) +
      (b.trills.isNotEmpty ? 1.3 : 0.0) +
      (b.harmonics.containsValue(harmonicNatural) || b.ghosts.isNotEmpty ? 0.6 : 0.0);
  return math.max(w, twoDigits ? 2.3 : 1.6) + bend + slide;
}

/// Breite eines Taktstrichs ohne Taktwechsel (in Linienabständen).
double _barWidth(BarKind k) => switch (k) {
  BarKind.normal => 1.4,
  BarKind.repeatBoth => 4.2,
  BarKind.last || BarKind.doubleLine => 2.0,
  _ => 3.0,
};

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

  final xs = <double>[], widths = <double>[], lineXs = <double>[];
  for (var i = 0; i < nx.length; i++) {
    final b = t.beats[i];
    xs.add(map(i, nx[i]));
    widths.add(nw[i] * factor(i));
    lineXs.add(
      b.bar && b.meter != null ? xs.last - widths.last / 2 + _barWidth(b.kind) * gap * factor(i) / 2 : xs.last,
    );
  }

  // 3. Von Hand gesetzte Schläge: Lage innerhalb ihres Takts. Die
  //    Taktstriche und die übrigen Schläge bleiben, wo sie sind; sie weichen
  //    nur aus, wenn es zu eng würde (Reihenfolge bleibt).
  if (t.beats.any((b) => !b.bar && b.at != null)) {
    final n = t.beats.length;
    final minGap = gap * 0.8;
    for (final m in measuresOf(t.beats)) {
      if (m.end <= m.start) continue;
      var any = false;
      for (var i = m.start; i < m.end; i++) {
        if (t.beats[i].at != null) any = true;
      }
      if (!any) continue;
      final (lo, hi) = _measureSpan(m.start, m.end, n, xs, widths, start, contentEnd - gap * _tail);
      // Letzter Takt ohne Taktstrich danach: rechts offen.
      final open = m.end >= n;
      final pinned = <int>{};
      var last = lo;
      for (var i = m.start; i < m.end; i++) {
        final at = t.beats[i].at;
        if (at == null) continue;
        final to = lo + at * (hi - lo);
        if (to <= last + minGap) continue;
        if (!open && to >= hi - gap * 0.5) continue;
        xs[i] = to;
        pinned.add(i);
        last = to;
      }
      // Vorwärts: nicht in den Schlag davor hinein …
      var prev = lo;
      for (var i = m.start; i < m.end; i++) {
        if (!pinned.contains(i)) xs[i] = math.max(xs[i], prev + minGap);
        prev = xs[i];
      }
      // … und rückwärts: nicht in den nächsten festen Schlag bzw. Taktstrich.
      var next = open ? double.infinity : hi;
      for (var i = m.end - 1; i >= m.start; i--) {
        if (!pinned.contains(i)) xs[i] = math.min(xs[i], next - minGap);
        next = xs[i];
      }
      for (var i = m.start; i < m.end; i++) {
        lineXs[i] = xs[i];
      }
    }
  }

  final endOfLast = xs.isEmpty ? start : xs.last + widths.last / 2;
  xs.add(endOfLast + gap * 1.1);
  widths.add(gap * 2.2);
  lineXs.add(xs.last);
  return TabLayout(
    origin: origin,
    gap: gap,
    width: width,
    xs: xs,
    slotWidths: widths,
    lineXs: lineXs,
    endX: math.max(contentEnd, endOfLast + gap * _tail),
    contentStart: start,
    contentEnd: contentEnd,
  );
}

/// Platz eines Takts (Schläge [from] bis vor [to]): vom Taktstrich davor
/// (bzw. dem Anfang) bis zum Taktstrich danach (bzw. [openEnd]).
(double, double) _measureSpan(
  int from,
  int to,
  int n,
  List<double> xs,
  List<double> widths,
  double start,
  double openEnd,
) {
  final lo = from > 0 ? xs[from - 1] + widths[from - 1] / 2 : start;
  final double hi;
  if (to < n) {
    hi = xs[to] - widths[to] / 2;
  } else {
    hi = math.max(openEnd, to > from ? xs[to - 1] + widths[to - 1] / 2 : lo);
  }
  return (lo, math.max(hi, lo + 1));
}

/// Platz des Takts, in dem der Schlag [i] steht (in Bildpunkten).
(double, double) measureSpanOf(TabBlock t, TabLayout l, int i) {
  for (final m in measuresOf(t.beats)) {
    if (i >= m.start && i < m.end) {
      return _measureSpan(
        m.start,
        m.end,
        t.beats.length,
        l.xs,
        l.slotWidths,
        l.contentStart,
        l.contentEnd - l.gap * _tail,
      );
    }
  }
  return (l.contentStart, l.contentEnd);
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

  // Endet die Zeile mit einem Taktstrich, hören die Linien genau dort auf.
  final lastBar = t.beats.isNotEmpty && t.beats.last.bar ? t.beats.last : null;
  final lineEnd = lastBar == null ? l.endX : l.lineXs[t.beats.length - 1] + _barRight(lastBar.kind, g);

  // Hintergrund (falls gewählt) hinter allem, mit etwas Rand.
  final bg = t.background != TabBlock.noBackground ? Color(t.background) : null;
  if (bg != null) {
    final above = _aboveUnits(t, l);
    // Triolen-Zahlen stehen unter den Balken.
    final below = t.beats.any((b) => b.triplet) ? 2.0 : 0.8;
    final r = Rect.fromLTRB(l.origin.dx - g * 0.6, l.top - g * above, lineEnd + g * 0.6, l.stemBottom + g * below);
    canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(g * 0.5)), Paint()..color = bg);
  }
  // Hinter Zahlen und „TAB“: der Hintergrund bzw. Weiss (die Seite).
  const white = Color(0xFFFFFFFF);
  final ground = bg != null ? Color.alphaBlend(bg, white) : white;

  _paintHighlights(canvas, t, l);

  // Linien und Anfangsstrich
  for (var s = 0; s < TabBlock.strings; s++) {
    canvas.drawLine(Offset(l.origin.dx, l.lineY(s)), Offset(lineEnd, l.lineY(s)), thin);
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
    _paintMeter(canvas, t.meter!, l.origin.dx + g * (_clef + 0.1 + _meterWidth(t.meter!) / 2), l, color);
  }

  final knockout = Paint()..color = ground;
  // Gehaltene Noten (Ziel eines Haltebogens) stehen in Klammern.
  final held = tieTargets(t.beats);
  for (var i = 0; i < t.beats.length; i++) {
    final b = t.beats[i];
    final cx = l.xs[i];
    // Grund hinter den Zahlen: farbig markiert mit der Farbe darunter.
    knockout.color = _groundOf(b, ground);
    if (b.bar) {
      _paintBar(canvas, b.kind, l.lineXs[i], l, color, stem.strokeWidth);
      // Taktwechsel: neue Taktart gleich nach dem Taktstrich.
      if (b.meter != null) {
        final m = _meterWidth(b.meter!) * l.slotWidths[i] / _naturalWidth(b);
        _paintMeter(canvas, b.meter!, cx + l.slotWidths[i] / 2 - m / 2, l, color);
      }
      continue;
    }
    if (b.isRest) {
      final p = _text(String.fromCharCode(_restGlyph(b.value)), g * 2.8, color, family: 'Bravura');
      final base = p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      final mid = l.top + g * 2.5;
      // Ganze Pause hängt an einer Linie, die anderen sitzen in der Mitte.
      final y = b.value == 1 ? l.lineY(2) : (b.value == 2 ? l.lineY(3) : mid);
      p.paint(canvas, Offset(cx - p.width / 2, y - base));
      for (var k = 0; k < b.dots; k++) {
        canvas.drawCircle(
          Offset(cx + p.width / 2 + g * (0.35 + k * 0.42), mid - g * 0.5),
          g * 0.17,
          Paint()..color = color,
        );
      }
      p.dispose();
      continue;
    }
    // Bundzahlen auf den Linien, mit weissem Grund (die Linie läuft nicht durch).
    for (final e in b.frets.entries) {
      // Dead Note: ein „x“ statt der Bundzahl.
      var label = e.value == ghostNote ? 'x' : '${e.value}';
      final isHeld = held.contains((i, e.key)) || b.tieIns.contains(e.key);
      // Gehaltene Note und Ghost Note: in Klammern; natürliches Flageolett: <12>.
      if (isHeld || b.ghosts.contains(e.key)) label = '($label)';
      if (b.harmonics[e.key] == harmonicNatural) label = '<$label>';
      final p = _text(label, g * 1.15, color);
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
      final numberWidth = p.width;
      p.dispose();
      // Triller: Bund, mit dem abgewechselt wird, klein in Klammern danach.
      final trill = b.trills[e.key];
      if (trill != null) {
        final q = _text('($trill)', g * _graceSize, color);
        final tx = cx + numberWidth / 2 + g * 0.15;
        final tr = Rect.fromLTWH(tx - g * 0.05, cy - g * 0.4, q.width + g * 0.1, g * 0.8);
        canvas.drawRect(tr, knockout);
        q.paint(canvas, Offset(tx, cy - q.height / 2));
        q.dispose();
      }
      // Vorschlagsnote: kleine Zahl gleich davor.
      final grace = b.graces[e.key];
      if (grace != null) {
        final q = _text('$grace', g * _graceSize, color);
        final gx = _graceX(b, e.key, cx, g);
        final gr = Rect.fromCenter(center: Offset(gx, cy), width: q.width + g * 0.2, height: g * 0.8);
        canvas.drawRect(gr, knockout);
        q.paint(canvas, Offset(gx - q.width / 2, cy - q.height / 2));
        q.dispose();
      }
    }
    // Hals (nicht bei ganzen Noten)
    if (b.value >= 2) canvas.drawLine(Offset(cx, l.stemTop), Offset(cx, l.stemBottom), stem);
    // Tremolo-Picking: Schrägstriche über dem Hals.
    final trem = b.mark(TabMark.tremolo);
    if (trem > 0) {
      final slash = Paint()
        ..color = color
        ..strokeWidth = g * 0.22
        ..strokeCap = StrokeCap.butt;
      final mid = l.stemTop + g * 1.0;
      for (var k = 0; k < trem; k++) {
        final y = mid + (k - (trem - 1) / 2) * g * 0.42;
        canvas.drawLine(Offset(cx - g * 0.42, y + g * 0.18), Offset(cx + g * 0.42, y - g * 0.18), slash);
      }
    }
    // Strumming: senkrechter Pfeil über alle Saiten vor dem Schlag.
    final strum = b.mark(TabMark.strum);
    if (strum == 1 || strum == 2) {
      final left = b.frets.keys.fold<double>(0, (m, st) => math.max(m, _halfNumber(b.frets[st]!, g)));
      final x = cx - left - g * 0.6;
      final arrow = Paint()
        ..color = color
        ..strokeWidth = math.max(0.8, g * 0.1);
      final tip = strum == 1 ? l.top - g * 0.2 : l.bottom + g * 0.2;
      final tail = strum == 1 ? l.bottom : l.top;
      final dir = strum == 1 ? 1.0 : -1.0; // vom Spitzen-Ende weg
      canvas.drawLine(Offset(x, tail), Offset(x, tip + dir * g * 0.4), arrow);
      canvas.drawPath(
        Path()
          ..moveTo(x, tip)
          ..lineTo(x - g * 0.28, tip + dir * g * 0.55)
          ..lineTo(x + g * 0.28, tip + dir * g * 0.55)
          ..close(),
        Paint()..color = color,
      );
    }
    if (b.dotted) {
      // Oben neben dem Hals: Dort liegen nie Balken (die sind unten, bis zu
      // drei übereinander bei 32steln).
      // Doppelt punktiert: zweiter Punkt gleich daneben.
      for (var k = 0; k < b.dots; k++) {
        canvas.drawCircle(Offset(cx + g * (0.5 + k * 0.42), l.stemTop + g * 0.45), g * 0.17, Paint()..color = color);
      }
    }
  }

  _paintTechniques(canvas, t, l, color, thin.strokeWidth);
  _paintMarks(canvas, t, l, color, thin.strokeWidth);
  _paintTriplets(canvas, t, l, color, stem.strokeWidth);

  // Balken (mehrere zusammen) und Notenfahnen (einzeln)
  final beam = Paint()..color = color;
  final sw = stem.strokeWidth;
  final thick = g * 0.45, step = g * 0.72;
  void bar(double x1, double x2, int level) {
    final y = l.stemBottom - level * step;
    // Bündig mit den Aussenkanten der Hälse.
    final left = math.min(x1, x2) - sw / 2, right = math.max(x1, x2) + sw / 2;
    canvas.drawRect(Rect.fromLTRB(left, y - thick, right, y), beam);
  }

  for (final group in beamGroups(t.beats)) {
    if (group.length == 1) {
      // Einzeln: Notenfahne aus der Notenschrift (Hals nach unten).
      final i = group.single;
      final glyph = switch (t.beats[i].value) {
        8 => 0xE241,
        16 => 0xE243,
        _ => 0xE245,
      };
      final p = _text(String.fromCharCode(glyph), g * 3.0, color, family: 'Bravura');
      final base = p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      // Die Fahne hängt mit ihrem Ursprung am Halsende.
      p.paint(canvas, Offset(l.xs[i] - sw / 2, l.stemBottom - base));
      p.dispose();
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
          // Kein Nachbar mit so vielen Balken: kurzer Stummel zur Gruppe hin.
          final dir = next != null ? 1.0 : -1.0;
          bar(l.xs[i], l.xs[i] + dir * g * 0.9, level);
        }
      }
    }
  }
}

/// Ziele von Haltebögen als (Schlag, Saite).
Set<(int, int)> tieTargets(List<TabBeat> beats) {
  final out = <(int, int)>{};
  for (var i = 0; i < beats.length; i++) {
    for (final st in beats[i].ties) {
      final j = _nextOnString(beats, i, st);
      if (j != null) out.add((j, st));
    }
  }
  return out;
}

/// Nächster Schlag nach [i] mit einer Bundzahl auf Saite [st].
int? _nextOnString(List<TabBeat> beats, int i, int st) {
  for (var k = i + 1; k < beats.length; k++) {
    if (!beats[k].bar && beats[k].frets.containsKey(st)) return k;
  }
  return null;
}

/// Art eines Bogens an einer Bundzahl.
enum TabArc { tie, tieIn, legato, grace }

/// Wo jeder Bogen liegt: über (true) oder unter (false) seinen Zahlen.
///
/// Haltebögen liegen gewöhnlich unter den Zahlen, Hammer-on/Pull-off
/// darüber. Teilen sich zwei Bögen benachbarter Saiten denselben
/// Zwischenraum an derselben Stelle, weicht einer auf die andere Seite aus –
/// am liebsten einer, der dann ganz ausserhalb der Linien liegt (über der
/// obersten bzw. unter der untersten Linie), sonst einer, dessen andere
/// Seite frei ist. Ein Hammer-on auf der untersten Saite bleibt oben (darunter
/// sind die Hälse).
Map<(int, int, TabArc), bool> arcSides(List<TabBeat> beats) {
  final arcs = <({int beat, int string, TabArc kind, double from, double to})>[];
  for (var i = 0; i < beats.length; i++) {
    final b = beats[i];
    if (b.bar) continue;
    for (final st in b.tieIns) {
      if (b.frets.containsKey(st)) arcs.add((beat: i, string: st, kind: TabArc.tieIn, from: i - 0.9, to: i.toDouble()));
    }
    for (final st in b.graces.keys) {
      arcs.add((beat: i, string: st, kind: TabArc.grace, from: i - 0.6, to: i.toDouble()));
    }
    for (final (kind, set) in [(TabArc.tie, b.ties), (TabArc.legato, b.legato)]) {
      for (final st in set) {
        if (!b.frets.containsKey(st)) continue;
        final j = _nextOnString(beats, i, st);
        arcs.add((beat: i, string: st, kind: kind, from: i.toDouble(), to: (j ?? i + 0.9).toDouble()));
      }
    }
  }
  arcs.sort((a, b) => a.from.compareTo(b.from));
  const last = TabBlock.strings - 1;
  // Zwischenraum k liegt zwischen Linie k − 1 und Linie k; 0 und
  // [TabBlock.strings] sind ausserhalb der Linien (dort ist immer Platz).
  int gapOf(int st, bool above) => above ? st : st + 1;
  bool outer(int gap) => gap == 0 || gap == TabBlock.strings;
  bool canFlip(TabArc kind, int st, bool above) =>
      !((kind == TabArc.legato || kind == TabArc.grace) && above && st == last);

  final side = <int, bool>{}; // Index in arcs → über den Zahlen
  bool overlaps(int a, int b) => arcs[a].from < arcs[b].to && arcs[b].from < arcs[a].to;
  List<int> blockers(int a, bool above) {
    final gap = gapOf(arcs[a].string, above);
    if (outer(gap)) return const [];
    return [
      for (final e in side.entries)
        if (e.key != a && gapOf(arcs[e.key].string, e.value) == gap && overlaps(a, e.key)) e.key,
    ];
  }

  for (var a = 0; a < arcs.length; a++) {
    final arc = arcs[a];
    final preferred = arc.kind == TabArc.legato || arc.kind == TabArc.grace;
    final inWay = blockers(a, preferred);
    if (inWay.isEmpty) {
      side[a] = preferred;
      continue;
    }
    // 1. Ein Bogen im Weg kann ganz nach aussen ausweichen.
    final toOuter = inWay.where(
      (o) => canFlip(arcs[o].kind, arcs[o].string, side[o]!) && outer(gapOf(arcs[o].string, !side[o]!)),
    );
    if (toOuter.length == inWay.length) {
      for (final o in inWay) {
        side[o] = !side[o]!;
      }
      side[a] = preferred;
      continue;
    }
    // 2. Dieser Bogen weicht auf seine andere Seite aus.
    if (canFlip(arc.kind, arc.string, preferred) && blockers(a, !preferred).isEmpty) {
      side[a] = !preferred;
      continue;
    }
    // 3. Die Bögen im Weg weichen auf ihre (freie) andere Seite aus. Geht
    //    auch das nicht, bleibt es an dieser Stelle eben eng.
    for (final o in inWay) {
      if (!canFlip(arcs[o].kind, arcs[o].string, side[o]!)) continue;
      side[o] = !side[o]!;
      if (blockers(o, side[o]!).isNotEmpty) side[o] = !side[o]!;
    }
    side[a] = preferred;
  }
  return {for (final e in side.entries) (arcs[e.key].beat, arcs[e.key].string, arcs[e.key].kind): e.value};
}

/// Grösse der Vorschlagsnoten (im Verhältnis zum Linienabstand).
const _graceSize = 0.8;

/// Mitte der Vorschlagsnote vor der Note auf Saite [st] (Platz dafür gibt
/// [_naturalWidth]).
double _graceX(TabBeat b, int st, double cx, double g) {
  final main = b.frets[st] ?? 0;
  final grace = b.graces[st] ?? 0;
  final slideIn = b.slideIns.containsKey(st) ? g * 0.9 : 0.0;
  return cx - _halfNumber(main, g) - g * 0.75 - _halfNumber(grace, g) * _graceSize - slideIn;
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
  final held = tieTargets(t.beats);
  final sides = arcSides(t.beats);
  // Grund hinter kleinen Buchstaben (H/P): Hintergrund bzw. Weiss.
  final knockout = Paint()
    ..color = t.background != TabBlock.noBackground
        ? Color.alphaBlend(Color(t.background), const Color(0xFFFFFFFF))
        : const Color(0xFFFFFFFF);
  final plain = knockout.color;
  for (var i = 0; i < t.beats.length; i++) {
    final b = t.beats[i];
    if (b.bar) continue;
    final cx = l.xs[i];
    knockout.color = _groundOf(b, plain);
    // Haltebogen von davor: kommt von links in die (eingeklammerte) Zahl.
    for (final st in b.tieIns) {
      final fret = b.frets[st];
      if (fret == null) continue;
      final up = sides[(i, st, TabArc.tieIn)] ?? false;
      final dir = up ? -1.0 : 1.0;
      final y = l.lineY(st) + dir * g * 0.55;
      final x2 = cx - g * 0.2 - _halfNumber(fret, g) * 0.6;
      final x1 = x2 - g * 1.4;
      canvas.drawPath(
        Path()
          ..moveTo(x1, y)
          ..quadraticBezierTo((x1 + x2) / 2, y + dir * g * 0.6, x2, y),
        line,
      );
    }
    // Haltebögen: flacher Bogen unter den Zahlen zur gehaltenen Note.
    for (final st in b.ties) {
      final fret = b.frets[st];
      final j = _nextOnString(t.beats, i, st);
      if (fret == null) continue;
      final up = sides[(i, st, TabArc.tie)] ?? false;
      final dir = up ? -1.0 : 1.0;
      final y = l.lineY(st) + dir * g * 0.55;
      final x1 = cx + g * 0.2;
      final double x2;
      if (j != null) {
        final to = t.beats[j].frets[st]!;
        x2 = l.xs[j] - g * 0.2 - (held.contains((j, st)) ? _halfNumber(to, g) * 0.6 : 0);
      } else {
        x2 = x1 + g * 1.4;
      }
      canvas.drawPath(
        Path()
          ..moveTo(x1, y)
          ..quadraticBezierTo((x1 + x2) / 2, y + dir * g * 0.6, x2, y),
        line,
      );
    }
    // Vorschlagsnoten: kleiner Bogen in die Hauptnote, mit „H“ bzw. „P“.
    for (final e in b.graces.entries) {
      final st = e.key, fret = b.frets[st];
      if (fret == null || fret == ghostNote) continue;
      final up = sides[(i, st, TabArc.grace)] ?? true;
      final dir = up ? -1.0 : 1.0;
      final y = l.lineY(st) + dir * g * 0.45;
      final x1 = _graceX(b, st, cx, g), x2 = cx - g * 0.05;
      final crest = y + dir * g * 0.35;
      canvas.drawPath(
        Path()
          ..moveTo(x1, y)
          ..quadraticBezierTo((x1 + x2) / 2, y + dir * g * 0.7, x2, y),
        line,
      );
      if (e.value == fret) continue;
      final outside = (up && st == 0) || (!up && st == TabBlock.strings - 1);
      final p = _text(fret > e.value ? 'H' : 'P', g * (outside ? 0.7 : 0.6), color, bold: true);
      final at = Offset(
        (x1 + x2) / 2 - p.width / 2,
        outside ? (up ? crest - g * 0.05 - p.height : crest + g * 0.05) : crest - p.height / 2,
      );
      canvas.drawRect((at & p.size).inflate(g * 0.05), knockout);
      p.paint(canvas, at);
      p.dispose();
    }
    // Hammer-on / Pull-off: Bogen über den Zahlen zur nächsten Note auf
    // derselben Saite, darüber klein „H“ (höher) bzw. „P“ (tiefer).
    for (final st in b.legato) {
      final fret = b.frets[st];
      if (fret == null) continue;
      final j = _nextOnString(t.beats, i, st);
      // Gewöhnlich darüber; liegt dort schon ein Bogen, darunter.
      final up = sides[(i, st, TabArc.legato)] ?? true;
      final dir = up ? -1.0 : 1.0;
      final y = l.lineY(st) + dir * g * 0.5;
      final x1 = cx + g * 0.15;
      final x2 = j != null ? l.xs[j] - g * 0.15 : x1 + g * 1.4;
      final peak = y + dir * g * 0.55;
      canvas.drawPath(
        Path()
          ..moveTo(x1, y)
          ..quadraticBezierTo((x1 + x2) / 2, peak + dir * g * 0.25, x2, y),
        line,
      );
      final to = j == null ? null : t.beats[j].frets[st];
      if (to == null || to == ghostNote || fret == ghostNote || to == fret) continue;
      // Ganz aussen (über der obersten bzw. unter der untersten Linie) steht
      // der Buchstabe neben dem Bogen; zwischen den Linien sitzt er kleiner
      // auf dessen Scheitel, damit er nicht in den nächsten Zwischenraum ragt.
      final outside = (up && st == 0) || (!up && st == TabBlock.strings - 1);
      final p = _text(to > fret ? 'H' : 'P', g * (outside ? 0.8 : 0.7), color, bold: true);
      final crest = (y + peak + dir * g * 0.25) / 2; // höchster Punkt des Bogens
      final at = Offset(
        (x1 + x2) / 2 - p.width / 2,
        outside ? (up ? peak - g * 0.05 - p.height : peak + g * 0.05) : crest - p.height / 2,
      );
      canvas.drawRect((at & p.size).inflate(g * 0.06), knockout);
      p.paint(canvas, at);
      p.dispose();
    }
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
    // Slide in den Ton: kurze Linie vor der Zahl, die von unten steigt bzw.
    // von oben fällt.
    for (final e in b.slideIns.entries) {
      final fret = b.frets[e.key];
      if (fret == null) continue;
      final y = l.lineY(e.key);
      final x2 = cx - _halfNumber(fret, g) - g * 0.15;
      final dy = g * 0.3 * e.value;
      canvas.drawLine(Offset(x2 - g * 0.95, y + dy), Offset(x2, y - dy), line);
    }
    // Slide aus dem Ton: kurze Linie nach der Zahl, nach oben bzw. unten.
    for (final e in b.slideOuts.entries) {
      final fret = b.frets[e.key];
      if (fret == null) continue;
      final y = l.lineY(e.key);
      final x1 = cx + _halfNumber(fret, g) + g * 0.15;
      final dy = g * 0.3 * e.value;
      canvas.drawLine(Offset(x1, y + dy), Offset(x1 + g * 0.95, y - dy), line);
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

/// Grund hinter Zahlen eines Schlags: bei farbiger Markierung die Farbe
/// über dem Grund der Tabulatur, sonst dieser.
Color _groundOf(TabBeat b, Color ground) => b.highlight == 0 ? ground : Color.alphaBlend(Color(b.highlight), ground);

/// Farbige Markierungen hinter den Schlägen (wie mit dem Leuchtstift):
/// Aufeinanderfolgende Schläge gleicher Farbe bilden eine Fläche, auch über
/// einen Taktstrich hinweg.
void _paintHighlights(Canvas canvas, TabBlock t, TabLayout l) {
  final g = l.gap;
  int? start;
  var end = -1, color = 0;
  void flush() {
    final s = start;
    if (s == null) return;
    final r = Rect.fromLTRB(
      l.xs[s] - l.slotWidths[s] / 2,
      l.top - g * 0.75,
      l.xs[end] + l.slotWidths[end] / 2,
      l.bottom + g * 0.75,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(g * 0.35)), Paint()..color = Color(color));
    start = null;
  }

  for (var i = 0; i < t.beats.length; i++) {
    final b = t.beats[i];
    if (b.bar) {
      if (start == null) continue;
      // Taktstrich mitten in einer Fläche: nur, wenn es danach gleich weitergeht.
      var j = i + 1;
      while (j < t.beats.length && t.beats[j].bar) {
        j++;
      }
      if (j < t.beats.length && t.beats[j].highlight == color) {
        end = i;
      } else {
        flush();
      }
      continue;
    }
    if (b.highlight == 0) {
      flush();
    } else if (start != null && b.highlight == color) {
      end = i;
    } else {
      flush();
      start = i;
      end = i;
      color = b.highlight;
    }
  }
  flush();
}

/// Palm Mute bzw. Let ring für die Schläge [first]..[last]: kleiner Text
/// über den Linien, bei mehreren Schlägen eine gestrichelte Linie bis zum
/// letzten mit einem kurzen Strich am Ende.
void _paintSpan(
  Canvas canvas,
  TabBlock t,
  TabLayout l,
  Color color,
  double lineWidth,
  int first,
  int last,
  double y,
  String text,
) {
  final g = l.gap;
  final dash = Paint()
    ..color = color
    ..strokeWidth = math.max(0.7, lineWidth);
  final p = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: 'VoltiSans',
        fontSize: g * 0.85,
        color: color,
        height: 1,
        fontStyle: FontStyle.italic,
        fontVariations: const [FontVariation.weight(600)],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final x0 = l.xs[first] - p.width / 2;
  p.paint(canvas, Offset(x0, y - p.height / 2));
  final from = x0 + p.width + g * 0.25, to = l.xs[last] + g * 0.6;
  if (last > first && to > from + g * 0.3) {
    for (var x = from; x < to; x += g * 0.55) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + g * 0.3, to), y), dash);
    }
    canvas.drawLine(Offset(to, y), Offset(to, y + g * 0.4), dash);
  }
  p.dispose();
}

/// Taktart (Zähler oben, Nenner unten) mit der Mitte bei [cx].
void _paintMeter(Canvas canvas, String meter, double cx, TabLayout l, Color color) {
  final g = l.gap;
  for (final (i, part) in meter.split('/').indexed) {
    final p = _text(_meterDigits(part), g * 2.6, color, family: 'Bravura');
    final base = p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    // Die Ziffern sind um ihre Grundlinie herum gezeichnet.
    final cy = l.top + g * (i == 0 ? 1.6 : 3.4);
    p.paint(canvas, Offset(cx - p.width / 2, cy - base));
    p.dispose();
  }
}

/// Wie weit ein Taktstrich rechts über seine Mitte hinausreicht.
double _barRight(BarKind k, double g) => switch (k) {
  BarKind.normal => 0,
  BarKind.repeatEnd || BarKind.last => g * 0.45,
  BarKind.doubleLine => g * 0.25,
  BarKind.repeatStart => g * 0.25,
  BarKind.repeatBoth => g * 0.25,
};

/// Taktstrich zeichnen: normal, Wiederholung Anfang/Ende/beides, Schlussstrich.
void _paintBar(
  Canvas canvas,
  BarKind kind,
  double cx,
  TabLayout l,
  Color color,
  double thinWidth, {
  double? dotRadius,
  double? thickWidth,
}) {
  final g = l.gap;
  final thick = thickWidth ?? g * 0.42;
  final fill = Paint()..color = color;
  void thinAt(double x) => canvas.drawRect(Rect.fromLTRB(x - thinWidth / 2, l.top, x + thinWidth / 2, l.bottom), fill);
  void thickAt(double x) => canvas.drawRect(Rect.fromLTRB(x - thick / 2, l.top, x + thick / 2, l.bottom), fill);
  void dotsAt(double x) {
    // In den Zwischenräumen über und unter der Mitte (6 Linien).
    for (final y in [l.top + g * 1.5, l.top + g * 3.5]) {
      canvas.drawCircle(Offset(x, y), dotRadius ?? g * 0.22, fill);
    }
  }

  switch (kind) {
    case BarKind.normal:
      thinAt(cx);
    case BarKind.last:
      thinAt(cx - g * 0.35);
      thickAt(cx + g * 0.25);
    case BarKind.doubleLine:
      thinAt(cx - g * 0.22);
      thinAt(cx + g * 0.22);
    case BarKind.repeatEnd:
      dotsAt(cx - g * 0.75);
      thinAt(cx - g * 0.2);
      thickAt(cx + g * 0.25);
    case BarKind.repeatStart:
      thickAt(cx - g * 0.25);
      thinAt(cx + g * 0.2);
      dotsAt(cx + g * 0.75);
    case BarKind.repeatBoth:
      dotsAt(cx - g * 1.15);
      thinAt(cx - g * 0.6);
      thickAt(cx);
      thinAt(cx + g * 0.6);
      dotsAt(cx + g * 1.15);
  }
}

/// Triolen: eine „3“ unter den Balken; sind die Schläge nicht durch einen
/// Balken verbunden (z. B. Viertel-Triole), dazu eine Klammer.
void _paintTriplets(Canvas canvas, TabBlock t, TabLayout l, Color color, double lineWidth) {
  final g = l.gap;
  final beamed = beamGroups(t.beats);
  for (final grp in tripletGroups(t.beats)) {
    final x1 = l.xs[grp.start], x2 = l.xs[grp.end];
    final cx = (x1 + x2) / 2;
    final p = TextPainter(
      text: TextSpan(
        text: '3',
        style: TextStyle(
          fontFamily: 'VoltiSans',
          fontSize: g * 1.05,
          color: color,
          height: 1,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final y = l.stemBottom + g * 0.45;
    final inOneBeam = beamed.any((b) => b.contains(grp.start) && b.contains(grp.end) && b.length > 1);
    if (!inOneBeam && grp.end > grp.start) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = lineWidth
        ..style = PaintingStyle.stroke;
      final yb = y + p.height / 2;
      final gapHalf = p.width / 2 + g * 0.25;
      canvas.drawPath(
        Path()
          ..moveTo(x1, yb - g * 0.3)
          ..lineTo(x1, yb)
          ..lineTo(cx - gapHalf, yb)
          ..moveTo(cx + gapHalf, yb)
          ..lineTo(x2, yb)
          ..lineTo(x2, yb - g * 0.3),
        paint,
      );
    }
    p.paint(canvas, Offset(cx - p.width / 2, y));
    p.dispose();
  }
}

/// Kleines Symbol eines Taktstrichs (für die Knöpfe im Tab-Fenster).
class BarKindIcon extends StatelessWidget {
  const BarKindIcon(this.kind, {super.key, this.color});
  final BarKind kind;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(24, 22),
    painter: _BarIconPainter(kind, color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000)),
  );
}

class _BarIconPainter extends CustomPainter {
  _BarIconPainter(this.kind, this.color);
  final BarKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Eigene, gut lesbare Zeichnung (auf der Seite wären die Abstände zu eng).
    final fill = Paint()..color = color;
    const top = 2.0;
    final bottom = size.height - 2;
    final cx = size.width / 2;
    void thin(double x) => canvas.drawRect(Rect.fromLTRB(x - 0.8, top, x + 0.8, bottom), fill);
    void thick(double x) => canvas.drawRect(Rect.fromLTRB(x - 1.7, top, x + 1.7, bottom), fill);
    void dots(double x) {
      for (final y in [size.height * 0.36, size.height * 0.64]) {
        canvas.drawCircle(Offset(x, y), 1.8, fill);
      }
    }

    switch (kind) {
      case BarKind.normal:
        thin(cx);
      case BarKind.repeatStart:
        thick(cx - 5);
        thin(cx);
        dots(cx + 5);
      case BarKind.repeatEnd:
        dots(cx - 5);
        thin(cx);
        thick(cx + 5);
      case BarKind.repeatBoth:
        dots(cx - 8);
        thin(cx - 4);
        thick(cx);
        thin(cx + 4);
        dots(cx + 8);
      case BarKind.doubleLine:
        thin(cx - 2.5);
        thin(cx + 2.5);
      case BarKind.last:
        thin(cx - 3);
        thick(cx + 2);
    }
  }

  @override
  bool shouldRepaint(_BarIconPainter old) => old.kind != kind || old.color != color;
}

/// Knopf-Symbol für einen Slide in den Ton hinein ([into]) oder aus ihm
/// heraus: eine Linie (Saite) mit „5“ und dem kurzen Slide davor bzw. danach.
/// [dir] +1 = steigend (von unten bzw. nach oben), −1 = fallend.
class SlideIcon extends StatelessWidget {
  const SlideIcon({super.key, required this.into, required this.dir, this.color});
  final bool into;
  final int dir;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(30, 22),
    painter: _SlideIconPainter(into, dir, color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000)),
  );
}

class _SlideIconPainter extends CustomPainter {
  _SlideIconPainter(this.into, this.dir, this.color);
  final bool into;
  final int dir;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final number = TextPainter(
      text: TextSpan(
        text: '5',
        style: TextStyle(fontFamily: 'VoltiSans', fontSize: 13, fontWeight: FontWeight.w600, color: color, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final nx = into ? size.width - number.width - 3 : 3.0;
    number.paint(canvas, Offset(nx, cy - number.height / 2));
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final dy = 5.0 * dir;
    if (into) {
      final x2 = nx - 2;
      canvas.drawLine(Offset(x2 - 11, cy + dy), Offset(x2, cy - dy), line);
    } else {
      final x1 = nx + number.width + 2;
      canvas.drawLine(Offset(x1, cy + dy), Offset(x1 + 11, cy - dy), line);
    }
    number.dispose();
  }

  @override
  bool shouldRepaint(_SlideIconPainter old) => old.into != into || old.dir != dir || old.color != color;
}

/// Zeichen über den Linien, die über einen Schlag hinaus laufen. Jedes
/// bekommt die unterste Zeile, die an seiner Stelle noch frei ist; so bleibt
/// es kompakt (Wunsch des Besitzers: wenig Platz).
enum _Row { palmMute, letRing, rake, vibrato, trill, whammy }

/// Ein Zeichen in einer Zeile: Art, Schläge [first]..[last], Ausdehnung und Zeile.
class _Segment {
  _Segment(this.kind, this.first, this.last, this.x1, this.x2);
  final _Row kind;
  final int first, last;
  final double x1, x2;
  int row = 0;
}

/// Breite eines kleinen Textes über den Linien (in Linienabständen, grob).
double _labelWidth(String s) => s.length * 0.48;

List<_Segment> _segmentsOf(TabBlock t, TabLayout l) {
  final g = l.gap;
  final out = <_Segment>[];
  // Palm Mute und Let ring: zusammenhängende Gruppen (Taktstriche unterbrechen
  // nicht, Pausen schon).
  void groups(_Row kind, bool Function(TabBeat) on, String text) {
    int? start, end;
    for (var i = 0; i <= t.beats.length; i++) {
      final b = i < t.beats.length ? t.beats[i] : null;
      if (b != null && b.bar) continue;
      if (b != null && on(b)) {
        start ??= i;
        end = i;
      } else if (start != null) {
        final x1 = l.xs[start] - g * _labelWidth(text) / 2;
        final x2 = math.max(l.xs[end!] + g * 0.6, x1 + g * _labelWidth(text));
        out.add(_Segment(kind, start, end, x1, x2));
        start = end = null;
      }
    }
  }

  groups(_Row.palmMute, (b) => b.palmMute, 'P.M.');
  groups(_Row.letRing, (b) => b.mark(TabMark.letRing) != 0, 'let ring');
  for (var i = 0; i < t.beats.length; i++) {
    final b = t.beats[i];
    if (b.bar) continue;
    final cx = l.xs[i];
    if (b.mark(TabMark.rake) != 0) out.add(_Segment(_Row.rake, i, i, cx - g * 3.4, cx - g * 0.3));
    if (b.mark(TabMark.vibrato) != 0) out.add(_Segment(_Row.vibrato, i, i, cx - g * 0.3, _spanEnd(t, l, i)));
    if (b.trills.isNotEmpty) {
      out.add(_Segment(_Row.trill, i, i, cx - g * 0.1, math.max(_spanEnd(t, l, i), cx + g * 1.2)));
    }
    if (b.mark(TabMark.whammy) != 0) out.add(_Segment(_Row.whammy, i, i, cx, cx + g * 2.7));
  }
  // Zeilen verteilen: zuerst nach Art (Palm Mute zuunterst), dann von links.
  out.sort((p, q) => p.kind != q.kind ? p.kind.index.compareTo(q.kind.index) : p.x1.compareTo(q.x1));
  final placed = <_Segment>[];
  for (final seg in out) {
    var row = 0;
    // Gleiche Art darf direkt anschliessen (z. B. Vibrato über mehrere Schläge).
    bool clash(_Segment o) {
      final pad = o.kind == seg.kind ? 0.0 : g * 0.2;
      return o.row == row && o.x1 < seg.x2 + pad && seg.x1 < o.x2 + pad;
    }

    while (placed.any(clash)) {
      row++;
    }
    seg.row = row;
    placed.add(seg);
  }
  return out;
}

/// Mitte der Zeile [k] über der obersten Linie.
double _rowY(TabLayout l, int k) => l.top - l.gap * (0.85 + k * 1.05);

/// Höchste belegte Zeile um die Stelle [x] herum, ±[half] (−1 = keine).
int _topRowAt(List<_Segment> segs, double x, double half) {
  var top = -1;
  for (final s in segs) {
    if (s.x1 <= x + half && x - half <= s.x2) top = math.max(top, s.row);
  }
  return top;
}

/// Zeichen eines Schlags, die übereinander über den Zeilen stehen.
List<String> _stackOf(TabBeat b) => [
  if (b.staccato) 'stacc',
  if (b.accent) 'acc',
  if (b.mark(TabMark.pick) != 0) 'pick',
  if (b.harmonics.values.any((h) => h != harmonicNatural)) 'harm',
  if (b.mark(TabMark.tap) != 0) 'tap',
  if (b.mark(TabMark.strum) == 3) 'rasg',
  if (b.mark(TabMark.fermata) != 0) 'fer',
];

/// Wie weit die Tabulatur über die oberste Linie hinausreicht (in
/// Linienabständen), für den Hintergrund.
double _aboveUnits(TabBlock t, TabLayout l) {
  final segs = _segmentsOf(t, l);
  var u = 1.0;
  for (final s in segs) {
    u = math.max(u, 0.85 + s.row * 1.05 + 0.6);
  }
  for (var i = 0; i < t.beats.length; i++) {
    final b = t.beats[i];
    if (b.bar) continue;
    final stack = _stackOf(b);
    if (stack.isEmpty) continue;
    final rows = _topRowAt(segs, l.xs[i], l.gap * 0.7) + 1;
    u = math.max(u, 0.9 + rows * 1.05 + (stack.length - 1) * 0.85 + (stack.last == 'fer' ? 1.0 : 0.6));
  }
  if (t.beats.any((b) => b.bends.isNotEmpty)) u = math.max(u, 2.4);
  return u;
}

/// Wellenlinie von [x1] bis [x2] auf der Höhe [y] (Vibrato, Triller).
void _wave(Canvas canvas, double x1, double x2, double y, double g, Paint paint, {bool wide = false}) {
  final len = g * (wide ? 0.9 : 0.6), amp = g * (wide ? 0.32 : 0.2);
  if (x2 - x1 < len) return;
  final path = Path()..moveTo(x1, y);
  var x = x1, up = true;
  while (x + len / 2 <= x2) {
    path.quadraticBezierTo(x + len / 4, y + (up ? -amp : amp), x + len / 2, y);
    x += len / 2;
    up = !up;
  }
  canvas.drawPath(path, paint);
}

/// Bis wohin ein Zeichen ab Schlag [i] reicht: kurz vor den nächsten
/// Schlag bzw. ans Ende seines Platzes.
double _spanEnd(TabBlock t, TabLayout l, int i) {
  for (var k = i + 1; k < t.beats.length; k++) {
    if (!t.beats[k].bar) return l.xs[k] - l.gap * 0.35;
  }
  return l.xs[i] + l.slotWidths[i] / 2;
}

/// Zeichen über den Linien: Palm Mute, Let ring, Rake, Vibrato, Triller,
/// Hebel (je eine Zeile), darüber pro Schlag Staccato, Akzent,
/// Anschlagsrichtung, Flageolett, Tapping/Slap/Pop, rasg. und Fermate.
void _paintMarks(Canvas canvas, TabBlock t, TabLayout l, Color color, double lineWidth) {
  final g = l.gap;
  final segs = _segmentsOf(t, l);
  final line = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = math.max(0.9, lineWidth * 1.4);
  final fill = Paint()..color = color;
  TextPainter label(String s, double size, {bool italic = true, int weight = 600, String family = 'VoltiSans'}) =>
      TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            fontFamily: family,
            fontSize: size,
            color: color,
            height: 1,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            fontVariations: [FontVariation.weight(weight.toDouble())],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  for (final seg in segs) {
    final y = _rowY(l, seg.row);
    final i = seg.first;
    final cx = l.xs[i];
    final b = t.beats[i];
    switch (seg.kind) {
      case _Row.palmMute:
        _paintSpan(canvas, t, l, color, lineWidth, seg.first, seg.last, y, 'P.M.');
      case _Row.letRing:
        _paintSpan(canvas, t, l, color, lineWidth, seg.first, seg.last, y, 'let ring');
      case _Row.rake:
        // „rake“ und eine gepunktete Linie mit Pfeil bis zum Schlag.
        final p = label('rake', g * 0.75);
        final x0 = cx - g * 3.4;
        p.paint(canvas, Offset(x0, y - p.height / 2));
        final from = x0 + p.width + g * 0.2, to = cx - g * 0.35;
        for (var x = from; x < to - g * 0.3; x += g * 0.32) {
          canvas.drawCircle(Offset(x, y), g * 0.07, fill);
        }
        canvas.drawPath(
          Path()
            ..moveTo(to, y)
            ..lineTo(to - g * 0.4, y - g * 0.2)
            ..lineTo(to - g * 0.4, y + g * 0.2)
            ..close(),
          fill,
        );
        p.dispose();
      case _Row.vibrato:
        _wave(canvas, cx - g * 0.3, _spanEnd(t, l, i), y, g, line, wide: b.mark(TabMark.vibrato) == 2);
      case _Row.trill:
        final p = label('tr', g * 0.95, weight: 700);
        final x0 = cx - g * 0.4;
        p.paint(canvas, Offset(x0, y - p.height / 2));
        _wave(canvas, x0 + p.width + g * 0.15, seg.x2, y, g, line);
        p.dispose();
      case _Row.whammy:
        final w = b.mark(TabMark.whammy);
        final top = y - g * 0.4, low = y + g * 0.4;
        final path = Path()..moveTo(cx, top);
        final double end;
        if (w ~/ 10 == 1) {
          // Dip: kurz hinunter und wieder hinauf.
          path
            ..lineTo(cx + g * 0.6, low)
            ..lineTo(cx + g * 1.2, top);
          end = cx + g * 1.2;
        } else {
          // Dive: hinunter und unten bleiben.
          path.lineTo(cx + g * 1.3, low);
          end = cx + g * 1.3;
        }
        canvas.drawPath(path, line);
        final p = label(whammyLabel(w), g * 0.75, italic: false);
        p.paint(canvas, Offset(end + g * 0.1, top - p.height * 0.2));
        p.dispose();
    }
  }

  // Pro Schlag übereinander, über den Zeilen an seiner Stelle.
  for (var i = 0; i < t.beats.length; i++) {
    final b = t.beats[i];
    if (b.bar) continue;
    final cx = l.xs[i];
    var y = l.top - g * (0.9 + (_topRowAt(segs, cx, g * 0.7) + 1) * 1.05);
    for (final item in _stackOf(b)) {
      switch (item) {
        case 'stacc':
          canvas.drawCircle(Offset(cx, y), g * 0.2, fill);
        case 'acc':
          final w = g * 0.55, h = g * 0.3;
          canvas.drawPath(
            Path()
              ..moveTo(cx - w, y - h)
              ..lineTo(cx + w, y)
              ..lineTo(cx - w, y + h),
            line,
          );
        case 'pick':
          // Abschlag (⊓) bzw. Aufschlag (V) aus der Notenschrift.
          final p = _text(
            String.fromCharCode(b.mark(TabMark.pick) == 1 ? 0xE610 : 0xE612),
            g * 2.2,
            color,
            family: 'Bravura',
          );
          final baseLine = p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
          p.paint(canvas, Offset(cx - p.width / 2, y + g * 0.3 - baseLine));
          p.dispose();
        case 'harm':
          final pinch = b.harmonics.values.contains(harmonicPinch);
          final p = label(pinch ? 'P.H.' : 'A.H.', g * 0.75);
          p.paint(canvas, Offset(cx - p.width / 2, y - p.height / 2));
          p.dispose();
        case 'tap':
          final p = label(['T', 'S', 'P'][b.mark(TabMark.tap) - 1], g * 0.95, italic: false, weight: 700);
          p.paint(canvas, Offset(cx - p.width / 2, y - p.height / 2));
          p.dispose();
        case 'rasg':
          final p = label('rasg.', g * 0.75);
          p.paint(canvas, Offset(cx - p.width / 2, y - p.height / 2));
          p.dispose();
        case 'fer':
          final p = _text(String.fromCharCode(0xE4C0), g * 2.6, color, family: 'Bravura');
          final baseLine = p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
          p.paint(canvas, Offset(cx - p.width / 2, y + g * 0.35 - baseLine));
          p.dispose();
      }
      y -= g * 0.85;
    }
  }
}
