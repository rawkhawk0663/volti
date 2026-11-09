import 'package:flutter/painting.dart';

import '../../core/ink/stamp.dart';
import '../../core/ink/stamp_catalog.dart';
import 'custom_stamp_registry.dart';

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

/// Fläche eines eigenen Stempels mit der Höhe [height], so dass sein
/// Mittelpunkt (z. B. der Notenkopf) auf [at] liegt.
Rect customStampRect(String id, Offset at, double height) {
  final s = CustomStamps.instance?.byId(id);
  final aspect = s?.aspect ?? 1, ax = s?.anchorX ?? 0.5, ay = s?.anchorY ?? 0.5;
  final w = height * aspect;
  return Rect.fromLTWH(at.dx - ax * w, at.dy - ay * height, w, height);
}

/// Malt einen eigenen Stempel. Fehlt das Bild noch (z. B. vor dem Sync),
/// erscheint ein grauer Platzhalter.
void paintCustomStamp(Canvas canvas, String id, Offset at, double height, {double opacity = 1}) {
  final rect = customStampRect(id, at, height);
  final img = CustomStamps.instance?.image(id);
  if (img == null) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(height * 0.1)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Color.fromRGBO(120, 120, 120, 0.6 * opacity),
    );
    return;
  }
  canvas.drawImageRect(
    img,
    Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    rect,
    Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(0, 0, 0, opacity),
  );
}

/// Malt einen gesetzten Stempel auf einer Seite der Grösse [page].
void paintStamp(Canvas canvas, Size page, Stamp s, {double opacity = 1}) {
  final custom = s.custom;
  if (custom != null) {
    paintCustomStamp(
      canvas,
      custom,
      Offset(s.x * page.width, s.y * page.height),
      s.size * page.width,
      opacity: opacity,
    );
    return;
  }
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
  final custom = s.custom;
  if (custom != null) return customStampRect(custom, Offset(s.x * page.width, s.y * page.height), s.size * page.width);
  final g = stampGlyph(s.glyph);
  final fs = s.size * page.width;
  final w = (g?.width ?? 0.6) * fs, h = (g?.height ?? 0.6) * fs;
  return Rect.fromCenter(center: Offset(s.x * page.width, s.y * page.height), width: w, height: h);
}
