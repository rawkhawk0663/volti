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
/// Höhe eines Notensystems, wenn man nur waagrecht zieht (relativ zur
/// Seitenbreite; ≈ 7 mm auf A4, wie gedruckte Noten).
const kStaffHeight = 0.033;

/// Ab dieser senkrechten Bewegung (relativ zur Seitenbreite) bestimmt das
/// Ziehen die Höhe der Notenlinien.
const kStaffFreeHeight = 0.07;

/// Höhe einer Tabulatur (6 Linien), wenn man nur waagrecht zieht (≈ 12,5 mm
/// auf A4, gleich wie die Vorlage „Tabulatur“ für leere Seiten).
const kTabHeight = 0.06;

/// Ab dieser senkrechten Bewegung bestimmt das Ziehen die Höhe der Tabulatur.
const kTabFreeHeight = 0.085;

/// Breite der Notenlinien relativ zur eingestellten Breite.
const kStaffLineWidth = 0.45;

/// Öffnung von Crescendo/Decrescendo relativ zur Seitenbreite.
const kHairpinOpening = 0.016;

/// Höhe der Haken eines Hauses relativ zur Seitenbreite (≈ 5 mm auf A4).
const kVoltaHeight = 0.024;

/// Schriftgrösse der Nummer in einem Haus relativ zur Seitenbreite.
const kVoltaTextSize = kVoltaHeight * 0.62;

/// Ist das ein Haus (1., 2. … oder ohne Nummer)?
bool isVolta(ShapeKind k) => k == ShapeKind.volta || k == ShapeKind.voltaOpen;

/// Stelle (oben links, in Bildpunkten), an der die Nummer eines Hauses steht,
/// das von [a] nach [b] gezogen wurde: gleich rechts vom linken Haken, knapp
/// unter der Linie.
Offset voltaLabelAt(Offset a, Offset b, double pageWidth) {
  final h = pageWidth * kVoltaHeight;
  return Offset(math.min(a.dx, b.dx) + h * 0.28, a.dy + h * 0.08);
}

/// Ein Linienzug einer Form.
class ShapePiece {
  const ShapePiece(this.points, {this.closed = false, this.solid = false, this.widthFactor = 1});
  final List<Offset> points;

  /// Geschlossene Fläche, die man füllen kann (Rechteck, Ellipse).
  final bool closed;

  /// Immer in der Linienfarbe gefüllt (Pfeilspitze).
  final bool solid;

  /// Linienbreite relativ zur eingestellten Breite.
  final double widthFactor;
}

/// Können Formen dieser Art gefüllt werden?
bool shapeCanFill(ShapeKind kind) => kind == ShapeKind.rectangle || kind == ShapeKind.ellipse;

/// Crescendo und Decrescendo sind ein einziges Werkzeug: Die Gabel öffnet
/// sich in Zugrichtung (nach rechts gezogen = crescendo, nach links =
/// decrescendo). Gespeicherte Einstellungen mit „decrescendo“ gelten als Gabel.
ShapeKind normalizeShapeKind(ShapeKind k) => k == ShapeKind.decrescendo ? ShapeKind.crescendo : k;

/// Die Formen, die das Werkzeug anbietet (ohne das alte „Decrescendo“):
/// zuerst die allgemeinen, dann die Zeichen für Noten, zuletzt die Linien.
const offeredShapeKinds = [
  ShapeKind.line,
  ShapeKind.arrow,
  ShapeKind.rectangle,
  ShapeKind.ellipse,
  ShapeKind.crescendo,
  ShapeKind.slur,
  ShapeKind.volta,
  ShapeKind.voltaOpen,
  ShapeKind.staff,
  ShapeKind.tab,
];

List<ShapePiece> shapeGeometry(ShapeKind kind, Offset a, Offset b, double strokePx, {double? pageWidth}) {
  kind = normalizeShapeKind(kind);
  // Gabeln liegen immer waagrecht (sie werden nie schräg gebraucht).
  if (kind == ShapeKind.crescendo || isVolta(kind)) b = Offset(b.dx, a.dy);
  final d = b - a;
  final len = d.distance;
  if (len < 2) return const [];
  final dir = d / len;
  final normal = Offset(-dir.dy, dir.dx);
  switch (kind) {
    case ShapeKind.line:
      return [
        ShapePiece([a, b]),
      ];
    case ShapeKind.arrow:
      // Gefüllte, spitze Pfeilspitze. Ihre Grösse hängt nur von der Breite ab,
      // nicht von der Länge des Pfeils (Wunsch des Besitzers).
      final headLen = math.min(5.0 + strokePx * 4.5, len * 0.6);
      final halfWidth = headLen * 0.42;
      final base = b - dir * headLen;
      return [
        // Der Schaft endet in der Spitze, damit sein rundes Ende nicht vorsteht.
        ShapePiece([a, b - dir * (headLen * 0.6)]),
        ShapePiece([b, base + normal * halfWidth, base - normal * halfWidth, b], solid: true, widthFactor: 0.3),
      ];
    case ShapeKind.rectangle:
      final tl = Offset(math.min(a.dx, b.dx), math.min(a.dy, b.dy));
      final br = Offset(math.max(a.dx, b.dx), math.max(a.dy, b.dy));
      return [
        ShapePiece([tl, Offset(br.dx, tl.dy), br, Offset(tl.dx, br.dy), tl], closed: true),
      ];
    case ShapeKind.ellipse:
      final c = (a + b) / 2;
      final rx = (b.dx - a.dx).abs() / 2, ry = (b.dy - a.dy).abs() / 2;
      return [
        ShapePiece([
          for (var i = 0; i <= 64; i++)
            c + Offset(rx * math.cos(i / 64 * 2 * math.pi), ry * math.sin(i / 64 * 2 * math.pi)),
        ], closed: true),
      ];
    case ShapeKind.crescendo:
    case ShapeKind.decrescendo:
      // Gabel: spitz am Anfang, offen am Ende des Ziehens.
      // Öffnung ≈ 1.6 % der Seitenbreite (etwas mehr als ein Linienabstand auf A4),
      // bei sehr kurzen Gabeln höchstens halb so weit wie lang.
      final opening = math.min((pageWidth ?? 800) * kHairpinOpening, len * 0.5);
      final h = opening / 2;
      return [
        ShapePiece([b + normal * h, a, b - normal * h]),
      ];
    case ShapeKind.staff:
    case ShapeKind.tab:
      // Immer waagrecht. Die Länge kommt vom Ziehen nach links/rechts, die
      // Höhe vom Ziehen nach unten (oder oben). Fast nur waagrecht gezogen
      // → übliche Systemhöhe. Notenlinien: 5 Linien, Tabulatur: 6 (Saiten).
      final tab = kind == ShapeKind.tab;
      final lines = tab ? 6 : 5;
      final w = pageWidth ?? 800;
      final dy = b.dy - a.dy;
      if ((b.dx - a.dx).abs() < 4) return const [];
      // Die Höhe ändert sich erst nach einer deutlichen Bewegung nach unten
      // (oder oben). Kleines Wackeln beim waagrechten Ziehen bleibt ohne Folge.
      final free = dy.abs() >= w * (tab ? kTabFreeHeight : kStaffFreeHeight);
      final height = free ? dy.abs() : w * (tab ? kTabHeight : kStaffHeight);
      final down = dy >= 0 || !free ? 1.0 : -1.0;
      // Feiner als die eingestellte Breite (Wunsch des Besitzers): Notenlinien
      // sind auch im Druck dünner als Hälse und Bögen.
      return [
        for (var i = 0; i < lines; i++)
          ShapePiece([
            Offset(a.dx, a.dy + down * height * i / (lines - 1)),
            Offset(b.dx, a.dy + down * height * i / (lines - 1)),
          ], widthFactor: kStaffLineWidth),
      ];
    case ShapeKind.volta:
    case ShapeKind.voltaOpen:
      // Haus: waagrechte Linie mit Haken nach unten am Anfang und (geschlossen)
      // am Ende. Immer gleich hoch, egal wie lang. Die Nummer ist eine
      // Text-Notiz, die gleich nach dem Aufziehen zum Tippen aufgeht.
      final h = (pageWidth ?? 800) * kVoltaHeight;
      final l = math.min(a.dx, b.dx), r = math.max(a.dx, b.dx), y = a.dy;
      if (r - l < 4) return const [];
      return [
        ShapePiece([Offset(l, y + h), Offset(l, y), Offset(r, y), if (kind == ShapeKind.volta) Offset(r, y + h)]),
      ];
    case ShapeKind.slur:
      // Bogen nach oben (bzw. zur linken Seite der Zugrichtung).
      var bulge = normal * (len * 0.22);
      if (bulge.dy > 0) bulge = -bulge;
      final ctrl = (a + b) / 2 + bulge;
      return [
        ShapePiece([
          for (var i = 0; i <= 32; i++)
            () {
              final t = i / 32;
              return a * ((1 - t) * (1 - t)) + ctrl * (2 * (1 - t) * t) + b * (t * t);
            }(),
        ]),
      ];
  }
}
