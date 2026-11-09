import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../core/ink/stroke.dart';
import '../../app/theme.dart';
import '../../core/ink/tool_settings.dart';
import 'ink_controller.dart';
import 'perf_meter.dart';
import 'tool_controller.dart';
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
///
/// In der Spielansicht zeichnet der Stift sofort, sobald er gezogen wird.
/// Ein kurzes Antippen mit dem Stift bleibt ein Antippen (blättert um) und
/// hinterlässt keinen Punkt.
class InkLayer extends StatefulWidget {
  const InkLayer({super.key, required this.page, required this.controller, required this.tools});

  final int page;
  final InkController controller;
  final ToolController tools;

  @override
  State<InkLayer> createState() => _InkLayerState();
}

class _InkLayerState extends State<InkLayer> {
  int? _pointer;
  bool _erasing = false;

  /// Strich aus der Spielansicht: zählt erst, wenn der Stift weit genug
  /// gezogen wurde (sonst war es ein Antippen).
  bool _provisional = false;
  Offset _start = Offset.zero;
  DrawingPreset? _preset;
  final List<InkPoint> _points = [];
  Offset? _eraserPos;
  final _activeRepaint = ValueNotifier<int>(0);

  /// Zeitpunkt des letzten Stift-Ereignisses (für die Verzögerungsmessung).
  Duration _lastEventTime = Duration.zero;

  /// Letzte Positionen mit Zeit (Pixel) – für die Vorhersage.
  final List<(Offset, Duration)> _recent = [];

  /// Vorhersage: Wohin der Stift in Kürze kommt (nur angezeigt, nie
  /// gespeichert). Verkleinert den sichtbaren Abstand zur Stiftspitze.
  Offset? predictedPoint() {
    if (_recent.length < 3) return null;
    final (p0, t0) = _recent.first;
    final (p1, t1) = _recent.last;
    final dt = (t1 - t0).inMicroseconds / 1e6;
    if (dt <= 0) return null;
    final v = (p1 - p0) / dt; // Pixel pro Sekunde
    var ahead = v * 0.018; // ~18 ms voraus
    const maxAhead = 14.0;
    if (ahead.distance > maxAhead) ahead = ahead / ahead.distance * maxAhead;
    if (ahead.distance < 0.5) return null;
    return p1 + ahead;
  }

  /// Schon gemalter Anfang des entstehenden Strichs (als fertiges Bild), damit
  /// pro Bild nur die neuen Teilstücke gemalt werden – auch bei langen Strichen.
  ui.Image? _cachedStart;
  int _cachedPoints = 0;
  double _dpr = 1;

  void _resetCache() {
    _cachedStart?.dispose();
    _cachedStart = null;
    _cachedPoints = 0;
  }

  InkController get c => widget.controller;
  ToolController get tools => widget.tools;

  @override
  void dispose() {
    _resetCache();
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
    final mode = tools.mode;
    final instant = mode == ToolMode.read && e.kind == PointerDeviceKind.stylus && tools.instantPen;
    final drawing = mode == ToolMode.pen || mode == ToolMode.highlighter;
    if (!eraserEvent && !drawing && mode != ToolMode.eraser && !instant) return;
    _pointer = e.pointer;
    _erasing = eraserEvent || mode == ToolMode.eraser;
    _provisional = instant && !eraserEvent;
    _start = e.localPosition;
    _preset = tools.strokeStyle;
    _points.clear();
    _recent.clear();
    _resetCache();
    // Ein Radier-Zug = ein Schritt für "Rückgängig".
    if (_erasing) c.beginBatch();
    if (!_provisional) tools.isDrawing.value = true;
    _handle(e, size);
  }

  void _move(PointerEvent e, Size size) {
    if (e.pointer != _pointer) return;
    if (_provisional && (e.localPosition - _start).distance > kTouchSlop) {
      _provisional = false;
      tools.isDrawing.value = true;
    }
    _handle(e, size);
  }

  void _up(PointerEvent e, Size size) {
    if (e.pointer != _pointer) return;
    final preset = _preset;
    if (!_erasing && !_provisional && _points.isNotEmpty && preset != null) {
      c.addStroke(
        page: widget.page,
        tool: preset.tool,
        color: preset.color,
        width: preset.width,
        points: List.of(_points),
      );
    }
    if (_erasing) c.endBatch();
    _pointer = null;
    _provisional = false;
    _points.clear();
    _resetCache();
    _eraserPos = null;
    tools.isDrawing.value = false;
    _activeRepaint.value++;
  }

  void _handle(PointerEvent e, Size size) {
    _lastEventTime = e.timeStamp;
    _recent.add((e.localPosition, e.timeStamp));
    if (_recent.length > 4) _recent.removeAt(0);
    if (_erasing) {
      _eraserPos = e.localPosition;
      _eraseAt(e.localPosition, size);
    } else {
      final p = e.localPosition;
      _points.add(InkPoint(p.dx / size.width, p.dy / size.height, normalizedPressure(e)));
    }
    _activeRepaint.value++;
  }

  /// Ganze Elemente: kleiner, fester Fangradius. Teilweise: gewählte Grösse.
  double get eraserRadius => tools.eraserPartial ? tools.eraserRadius : 10;

  void _eraseAt(Offset pos, Size size) {
    final r = eraserRadius;
    final strokes = c.annotations.visibleStrokesOn(widget.page);
    if (tools.eraserPartial) {
      for (final s in strokes) {
        _eraseInside(s, pos, r, size);
      }
    } else {
      final hits = strokes.where((s) => _touches(s, pos, r, size)).toList();
      if (hits.isNotEmpty) c.eraseStrokes(hits);
    }
    // Text-Notizen werden immer ganz gelöscht.
    final eraser = Rect.fromCircle(center: pos, radius: r);
    final textHits = c.annotations.visibleTextsOn(widget.page).where((t) => textNoteBounds(t, size).overlaps(eraser));
    if (textHits.isNotEmpty) c.deleteTexts(textHits.toList());
  }

  /// Schnelle Vorprüfung über das umgebende Rechteck, dann genau.
  bool _touches(Stroke s, Offset pos, double r, Size size) {
    final half = s.width * size.width / 2;
    final b = s.bounds;
    final box = Rect.fromLTRB(b.left * size.width, b.top * size.height, b.right * size.width, b.bottom * size.height);
    if (!box.inflate(r + half * 1.7).contains(pos)) return false;
    Offset? prev;
    for (final p in s.points) {
      final cur = Offset(p.x * size.width, p.y * size.height);
      final d = prev == null ? (cur - pos).distance : _distToSegment(pos, prev, cur);
      if (d <= r + half) return true;
      prev = cur;
    }
    return false;
  }

  /// Teilweise radieren: entfernt nur den Teil des Strichs im Radierkreis.
  /// Der Rest wird zu einem oder mehreren neuen Strichen.
  void _eraseInside(Stroke s, Offset pos, double r, Size size) {
    if (!_touches(s, pos, r, size)) return;
    final reach = r + s.width * size.width / 2;
    Offset at(InkPoint p) => Offset(p.x * size.width, p.y * size.height);

    // Lange Teilstücke unterteilen, damit auch ein schnell gezogener Strich
    // genau an der berührten Stelle getrennt wird.
    final dense = <InkPoint>[];
    for (var i = 0; i < s.points.length; i++) {
      final p = s.points[i];
      if (i > 0) {
        final q = s.points[i - 1];
        final len = (at(p) - at(q)).distance;
        final steps = (len / (r * 0.4)).ceil();
        for (var k = 1; k < steps; k++) {
          final t = k / steps;
          dense.add(InkPoint(q.x + (p.x - q.x) * t, q.y + (p.y - q.y) * t, q.pressure + (p.pressure - q.pressure) * t));
        }
      }
      dense.add(p);
    }

    final pieces = <List<InkPoint>>[];
    var current = <InkPoint>[];
    var removedAny = false;
    for (final p in dense) {
      if ((at(p) - pos).distance <= reach) {
        removedAny = true;
        if (current.isNotEmpty) pieces.add(current);
        current = [];
      } else {
        current.add(p);
      }
    }
    if (current.isNotEmpty) pieces.add(current);
    if (!removedAny) return;
    // Winzige Reste (ein einzelner Punkt eines längeren Strichs) weglassen.
    pieces.removeWhere((piece) => piece.length < 2 && s.points.length > 1);
    c.replaceStroke(s, pieces);
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
    _dpr = MediaQuery.devicePixelRatioOf(context);
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
              // Fertige Striche als ein einziges Bild: Es wird nur neu erzeugt,
              // wenn sich die Striche ändern. Bei jedem Bild wird dann nur noch
              // dieses Bild gezeigt – statt alle Striche neu zu zeichnen.
              RepaintBoundary(
                child: _StrokesImage(controller: c, page: widget.page, size: size),
              ),
              // Eigene Ebene: Der entstehende Strich wird bei jeder Bewegung
              // neu gemalt, ohne alles andere mitzumalen.
              RepaintBoundary(
                child: CustomPaint(painter: _ActivePainter(this, repaint: _activeRepaint)),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Fertige Striche einer Seite, vorgerendert als Bild in voller Auflösung.
class _StrokesImage extends StatefulWidget {
  const _StrokesImage({required this.controller, required this.page, required this.size});
  final InkController controller;
  final int page;
  final Size size;

  @override
  State<_StrokesImage> createState() => _StrokesImageState();
}

class _StrokesImageState extends State<_StrokesImage> {
  ui.Image? _image;
  bool _dirty = true;
  Size? _renderedSize;
  double? _renderedDpr;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(_StrokesImage old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
      _dirty = true;
    }
    if (old.page != widget.page) _dirty = true;
  }

  // Höchstens ein neues Bild pro Bildschirm-Bild (auch beim schnellen Radieren).
  void _onChanged() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _image?.dispose();
    super.dispose();
  }

  void _render(double dpr) {
    final size = widget.size;
    final strokes = widget.controller.annotations.visibleStrokesOn(widget.page);
    _dirty = false;
    _renderedSize = size;
    _renderedDpr = dpr;
    final old = _image;
    if (strokes.isEmpty || size.isEmpty) {
      _image = null;
    } else {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(dpr);
      for (final s in strokes) {
        paintStroke(canvas, size, s.tool, Color(s.color), s.width, s.points);
      }
      final picture = recorder.endRecording();
      _image = picture.toImageSync((size.width * dpr).ceil(), (size.height * dpr).ceil());
      picture.dispose();
    }
    // Das alte Bild erst nach dem nächsten Bild freigeben.
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (_dirty || _renderedSize != widget.size || _renderedDpr != dpr) _render(dpr);
    final img = _image;
    return img == null ? const SizedBox.expand() : RawImage(image: img, fit: BoxFit.fill);
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
    if (state._erasing) {
      final pos = state._eraserPos;
      if (pos != null) {
        canvas.drawCircle(
          pos,
          state.eraserRadius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = VoltiColors.seafoam.withValues(alpha: 0.6),
        );
      }
      return;
    }
    final preset = state._preset;
    final pts = state._points;
    if (pts.isEmpty || preset == null || state._provisional) return;
    PerfMeter.instance.recordStrokeFrame(state._lastEventTime);

    // Deckende Stifte: den Anfang als fertiges Bild wiederverwenden und nur
    // die neuen Teilstücke malen. Textmarker und halbtransparente Stifte
    // werden als Ganzes gemalt (sonst wären die Übergänge sichtbar).
    final opaquePen = preset.tool == InkTool.pen && Color(preset.color).a >= 1.0;
    if (!opaquePen || pts.length < 48) {
      paintStroke(canvas, size, preset.tool, Color(preset.color), preset.width, pts);
      if (opaquePen) _paintPrediction(canvas, size, preset, pts);
      return;
    }
    final dpr = state._dpr;
    final dst = Offset.zero & size;
    void drawCached(Canvas c) {
      final img = state._cachedStart;
      if (img == null) return;
      c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, Paint());
    }

    if (pts.length - state._cachedPoints > 24) {
      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder)..scale(dpr);
      drawCached(c);
      paintPenSegments(c, size, Color(preset.color), preset.width, pts, state._cachedPoints, pts.length);
      final picture = recorder.endRecording();
      final img = picture.toImageSync((size.width * dpr).ceil(), (size.height * dpr).ceil());
      picture.dispose();
      final old = state._cachedStart;
      state._cachedStart = img;
      state._cachedPoints = pts.length;
      if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    drawCached(canvas);
    paintPenSegments(canvas, size, Color(preset.color), preset.width, pts, state._cachedPoints, pts.length);
    _paintPrediction(canvas, size, preset, pts);
  }

  /// Kurzes vorhergesagtes Stück am Ende des Strichs (nur Anzeige).
  void _paintPrediction(Canvas canvas, Size size, DrawingPreset preset, List<InkPoint> pts) {
    final p = state.predictedPoint();
    if (p == null || pts.isEmpty) return;
    final last = pts.last;
    final ahead = InkPoint(p.dx / size.width, p.dy / size.height, last.pressure);
    paintPenSegments(canvas, size, Color(preset.color), preset.width, [last, ahead], 1, 2);
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
  // Halbtransparente Stifte (z. B. Bleistift) als Ganzes durchsichtig machen,
  // sonst werden die Übergänge zwischen den Teilstücken dunkler.
  final translucent = color.a < 1.0;
  if (translucent) canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, color.a));
  final paint = Paint()
    ..color = translucent ? color.withValues(alpha: 1) : color
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  if (pts.length == 1) {
    canvas.drawCircle(at(pts.first), widthFor(pts.first.pressure) / 2, paint);
  } else {
    _drawSegments(canvas, size, paint, w, pts, 1, pts.length);
  }
  if (translucent) canvas.restore();
}

/// Malt die Teilstücke [from]..[to] eines deckenden Stift-Strichs.
void paintPenSegments(Canvas canvas, Size size, Color color, double width, List<InkPoint> pts, int from, int to) {
  final paint = Paint()
    ..color = color
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  _drawSegments(canvas, size, paint, width * size.width, pts, math.max(1, from), to);
}

void _drawSegments(Canvas canvas, Size size, Paint paint, double w, List<InkPoint> pts, int from, int to) {
  for (var i = from; i < to; i++) {
    final a = pts[i - 1], b = pts[i];
    paint.strokeWidth = math.max(0.5, w * (0.35 + 1.3 * (a.pressure + b.pressure) / 2));
    canvas.drawLine(Offset(a.x * size.width, a.y * size.height), Offset(b.x * size.width, b.y * size.height), paint);
  }
}
