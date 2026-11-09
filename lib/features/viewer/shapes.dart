import 'dart:math' as math;
import 'dart:ui';

import '../../core/ink/tool_settings.dart';

/// Linienzüge einer Form zwischen [a] (Start) und [b] (Ende), in Bildpunkten.
///
/// [pageWidth] ist die Breite der Seite in Bildpunkten. Daran richtet sich
/// die Öffnung von Crescendo und Decrescendo: Sie ist immer gleich weit,
/// egal wie lang man die Gabel zieht (wie im Notensatz üblich).
///
/// Formen werden als gewöhnliche Striche gespeichert – Radieren, Rückgängig
/// und Sync funktionieren dadurch wie bei allem anderen.
/// Öffnung von Crescendo/Decrescendo relativ zur Seitenbreite.
const kHairpinOpening = 0.016;

List<List<Offset>> shapeGeometry(ShapeKind kind, Offset a, Offset b, double strokePx, {double? pageWidth}) {
  final d = b - a;
  final len = d.distance;
  if (len < 2) return const [];
  final dir = d / len;
  final normal = Offset(-dir.dy, dir.dx);
  switch (kind) {
    case ShapeKind.line:
      return [
        [a, b],
      ];
    case ShapeKind.arrow:
      final head = (len * 0.25).clamp(8.0, 26.0) + strokePx * 2;
      Offset rot(Offset v, double angle) =>
          Offset(v.dx * math.cos(angle) - v.dy * math.sin(angle), v.dx * math.sin(angle) + v.dy * math.cos(angle));
      return [
        [a, b],
        [b + rot(-dir, 0.45) * head, b, b + rot(-dir, -0.45) * head],
      ];
    case ShapeKind.rectangle:
      final tl = Offset(math.min(a.dx, b.dx), math.min(a.dy, b.dy));
      final br = Offset(math.max(a.dx, b.dx), math.max(a.dy, b.dy));
      return [
        [tl, Offset(br.dx, tl.dy), br, Offset(tl.dx, br.dy), tl],
      ];
    case ShapeKind.ellipse:
      final c = (a + b) / 2;
      final rx = (b.dx - a.dx).abs() / 2, ry = (b.dy - a.dy).abs() / 2;
      return [
        [
          for (var i = 0; i <= 64; i++)
            c + Offset(rx * math.cos(i / 64 * 2 * math.pi), ry * math.sin(i / 64 * 2 * math.pi)),
        ],
      ];
    case ShapeKind.crescendo:
    case ShapeKind.decrescendo:
      // Gabel: öffnet sich beim Crescendo zum Ende hin, beim Decrescendo zum Anfang.
      // Öffnung ≈ 1.6 % der Seitenbreite (etwas mehr als ein Linienabstand auf A4),
      // bei sehr kurzen Gabeln höchstens halb so weit wie lang.
      final opening = math.min((pageWidth ?? 800) * kHairpinOpening, len * 0.5);
      final h = opening / 2;
      final tip = kind == ShapeKind.crescendo ? a : b;
      final open = kind == ShapeKind.crescendo ? b : a;
      return [
        [open + normal * h, tip, open - normal * h],
      ];
    case ShapeKind.slur:
      // Bogen nach oben (bzw. zur linken Seite der Zugrichtung).
      var bulge = normal * (len * 0.22);
      if (bulge.dy > 0) bulge = -bulge;
      final ctrl = (a + b) / 2 + bulge;
      return [
        [
          for (var i = 0; i <= 32; i++)
            () {
              final t = i / 32;
              return a * ((1 - t) * (1 - t)) + ctrl * (2 * (1 - t) * t) + b * (t * t);
            }(),
        ],
      ];
  }
}
