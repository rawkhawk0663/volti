import 'package:flutter/painting.dart';

import '../../core/ink/stamp.dart';
import '../../core/ink/stamp_catalog.dart';

const stampFontFamily = 'Bravura';

/// Malt ein Musiksymbol so, dass die Mitte seiner Tinte genau auf [center]
/// liegt (Masse aus der Schrift, siehe stamp_catalog.dart).
void paintGlyph(Canvas canvas, int codepoint, Offset center, double fontSize, Color color) {
  final g = stampGlyph(codepoint);
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(codepoint),
      style: TextStyle(fontFamily: stampFontFamily, fontSize: fontSize, color: color, height: 1),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final baseline = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  // Ursprung auf der Grundlinie so wählen, dass die Tinte mittig sitzt.
  final inkCx = g == null ? painter.width / 2 / fontSize : (g.left + g.right) / 2;
  final inkCy = g == null ? 0.0 : (g.bottom + g.top) / 2;
  final origin = Offset(center.dx - inkCx * fontSize, center.dy + inkCy * fontSize);
  painter.paint(canvas, Offset(origin.dx, origin.dy - baseline));
  painter.dispose();
}

/// Malt einen gesetzten Stempel auf einer Seite der Grösse [page].
void paintStamp(Canvas canvas, Size page, Stamp s, {double opacity = 1}) {
  final color = Color(s.color);
  paintGlyph(
    canvas,
    s.glyph,
    Offset(s.x * page.width, s.y * page.height),
    s.size * page.width,
    opacity < 1 ? color.withValues(alpha: color.a * opacity) : color,
  );
}

/// Fläche der Tinte eines Stempels (zum Antippen, Verschieben, Radieren).
Rect stampRect(Stamp s, Size page) {
  final g = stampGlyph(s.glyph);
  final fs = s.size * page.width;
  final w = (g?.width ?? 0.6) * fs, h = (g?.height ?? 0.6) * fs;
  return Rect.fromCenter(center: Offset(s.x * page.width, s.y * page.height), width: w, height: h);
}
