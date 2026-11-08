import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../core/ink/stroke.dart';
import '../../app/theme.dart';
import 'ink_controller.dart';
import 'text_layer.dart';

/// Rechnet den rohen Stiftdruck des Geräts auf 0..1 um.
/// Geräte ohne Drucksensor (Maus) liefern 0.5.
double normalizedPressure(PointerEvent e) {
  final range = e.pressureMax - e.pressureMin;
  if (range <= 0 || e.kind == PointerDeviceKind.mouse) return 0.5;
  return ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0);
}

/// Ist das ein Radier-Ereignis? Die Rückseite des Surface Pen meldet sich
/// als "invertierter Stift"; die Seitentaste des Stifts radiert ebenfalls.
bool isEraserEvent(PointerEvent e) =>
    e.kind == PointerDeviceKind.invertedStylus ||
    (e.kind == PointerDeviceKind.stylus && (e.buttons & kSecondaryStylusButton) != 0);

/// Ebene über einer Notenseite, die Stifteingaben in Striche umwandelt.
///
/// Fingereingaben werden hier bewusst ignoriert (Handballenerkennung):
/// Gezeichnet wird nur mit Stift oder Maus.
class InkLayer extends StatefulWidget {
  const InkLayer({super.key, required this.page, required this.controller});

  final int page;
  final InkController controller;

  @override
  State<InkLayer> createState() => _InkLayerState();
}

class _InkLayerState extends State<InkLayer> {
  int? _pointer;
  bool _erasing = false;
  InkTool _tool = InkTool.pen;
  final List<InkPoint> _points = [];
  Offset? _eraserPos;
  final _activeRepaint = ValueNotifier<int>(0);

  InkController get c => widget.controller;

  @override
  void dispose() {
    _activeRepaint.dispose();
    super.dispose();
  }

  bool _accepts(PointerDownEvent e) {
    switch (e.kind) {
      case PointerDeviceKind.stylus:
      case PointerDeviceKind.invertedStylus:
        return true;
      case PointerDeviceKind.mouse:
        return e.buttons == kPrimaryMouseButton;
      default:
        return false; // Finger, Trackpad: nie zeichnen
    }
  }

  void _down(PointerDownEvent e, Size size) {
    if (_pointer != null || !_accepts(e)) return;
    final eraserEvent = isEraserEvent(e);
    if ((c.mode == ToolMode.read || c.mode == ToolMode.text) && !eraserEvent) return;
    _pointer = e.pointer;
    _erasing = eraserEvent || c.mode == ToolMode.eraser;
    _tool = c.mode == ToolMode.highlighter ? InkTool.highlighter : InkTool.pen;
    _points.clear();
    _handle(e, size);
  }

  void _move(PointerEvent e, Size size) {
    if (e.pointer != _pointer) return;
    _handle(e, size);
  }

  void _up(PointerEvent e, Size size) {
    if (e.pointer != _pointer) return;
    if (!_erasing && _points.isNotEmpty) {
      c.addStroke(page: widget.page, tool: _tool, points: List.of(_points));
    }
    _pointer = null;
    _points.clear();
    _eraserPos = null;
    _activeRepaint.value++;
  }

  void _handle(PointerEvent e, Size size) {
    if (_erasing) {
      _eraserPos = e.localPosition;
      _eraseAt(e.localPosition, size);
    } else {
      final p = e.localPosition;
      _points.add(InkPoint(p.dx / size.width, p.dy / size.height, normalizedPressure(e)));
    }
    _activeRepaint.value++;
  }

  static const double eraserRadius = 14;

  void _eraseAt(Offset pos, Size size) {
    final hits = c.annotations.visibleStrokesOn(widget.page).where((s) {
      final half = s.width * size.width / 2;
      Offset? prev;
      for (final p in s.points) {
        final cur = Offset(p.x * size.width, p.y * size.height);
        final d = prev == null ? (cur - pos).distance : _distToSegment(pos, prev, cur);
        if (d <= eraserRadius + half) return true;
        prev = cur;
      }
      return false;
    }).toList();
    if (hits.isNotEmpty) c.eraseStrokes(hits);
    final eraser = Rect.fromCircle(center: pos, radius: eraserRadius);
    final textHits = c.annotations.visibleTextsOn(widget.page).where((t) => textNoteBounds(t, size).overlaps(eraser));
    if (textHits.isNotEmpty) c.deleteTexts(textHits.toList());
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) => _down(e, size),
          onPointerMove: (e) => _move(e, size),
          onPointerUp: (e) => _up(e, size),
          onPointerCancel: (e) => _up(e, size),
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                child: ListenableBuilder(
                  listenable: c,
                  builder: (context, _) =>
                      CustomPaint(painter: StrokesPainter(c.annotations.visibleStrokesOn(widget.page))),
                ),
              ),
              CustomPaint(painter: _ActivePainter(this, repaint: _activeRepaint)),
            ],
          ),
        );
      },
    );
  }
}

/// Zeichnet fertige Striche einer Seite.
class StrokesPainter extends CustomPainter {
  StrokesPainter(this.strokes);
  final List<Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      paintStroke(canvas, size, s.tool, Color(s.color), s.width, s.points);
    }
  }

  @override
  bool shouldRepaint(StrokesPainter old) => true;
}

class _ActivePainter extends CustomPainter {
  _ActivePainter(this.state, {required Listenable repaint}) : super(repaint: repaint);
  final _InkLayerState state;

  @override
  void paint(Canvas canvas, Size size) {
    final c = state.c;
    if (state._erasing) {
      final pos = state._eraserPos;
      if (pos != null) {
        canvas.drawCircle(
          pos,
          _InkLayerState.eraserRadius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = VoltiColors.seafoam.withValues(alpha: 0.6),
        );
      }
      return;
    }
    if (state._points.isEmpty) return;
    final hl = state._tool == InkTool.highlighter;
    paintStroke(
      canvas,
      size,
      state._tool,
      Color(hl ? InkController.highlighterColor : c.penColor),
      hl ? InkController.highlighterWidth : InkController.penWidth,
      state._points,
    );
  }

  @override
  bool shouldRepaint(_ActivePainter old) => true;
}

/// Gemeinsame Zeichenroutine für fertige und gerade entstehende Striche.
void paintStroke(Canvas canvas, Size size, InkTool tool, Color color, double width, List<InkPoint> pts) {
  if (pts.isEmpty) return;
  final w = width * size.width;
  Offset at(InkPoint p) => Offset(p.x * size.width, p.y * size.height);

  if (tool == InkTool.highlighter) {
    final path = Path()..moveTo(at(pts.first).dx, at(pts.first).dy);
    for (final p in pts.skip(1)) {
      path.lineTo(at(p).dx, at(p).dy);
    }
    if (pts.length == 1) path.lineTo(at(pts.first).dx + 0.1, at(pts.first).dy);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.square
        ..strokeJoin = StrokeJoin.round
        ..blendMode = BlendMode.multiply
        ..color = color,
    );
    return;
  }

  // Stift: Breite folgt dem Druck (0.35x bis 1.65x der Grundbreite).
  double widthFor(double pressure) => w * (0.35 + 1.3 * pressure);
  final paint = Paint()
    ..color = color
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  if (pts.length == 1) {
    canvas.drawCircle(at(pts.first), widthFor(pts.first.pressure) / 2, paint);
    return;
  }
  for (var i = 1; i < pts.length; i++) {
    paint.strokeWidth = math.max(0.5, widthFor((pts[i - 1].pressure + pts[i].pressure) / 2));
    canvas.drawLine(at(pts[i - 1]), at(pts[i]), paint);
  }
}
