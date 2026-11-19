import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;
import 'package:flutter/widgets.dart';

import '../../core/ink/annotation_layer.dart';
import '../../core/ink/selection.dart';
import '../../core/ink/stamp.dart';
import '../../core/ink/stroke.dart';
import '../../app/theme.dart';
import '../../core/ink/tool_settings.dart';
import 'ink_controller.dart';
import 'perf_meter.dart';
import 'shapes.dart';
import 'custom_stamp_registry.dart';
import 'page_export.dart';
import 'stamp_paint.dart';
import 'tool_controller.dart';
import 'text_layer.dart';
import '../../app/l10n.dart';

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
  const InkLayer({super.key, required this.page, required this.controller, required this.tools, this.pageImage});

  final int page;
  final InkController controller;
  final ToolController tools;

  /// Bild der Notenseite. Der Leuchtstift wird damit fest zu einem Bild
  /// verrechnet, damit beim Zeichnen nicht jedes Bild neu gemischt werden muss.
  final ui.Image? pageImage;

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

  /// Stempel: Vorschau-Position, oder ein Stempel, der gerade verschoben wird.
  Offset? _stampPos;
  String? _movingStampId;
  Offset _stampGrab = Offset.zero;

  /// Formen: Start- und Endpunkt beim Aufziehen.
  Offset? _shapeStart, _shapeEnd;

  /// Lasso: gezogene Linie (Pixel) bzw. laufendes Verschieben/Vergrössern.
  List<Offset>? _lasso;
  _SelectDrag? _selDrag;
  Offset _selStart = Offset.zero;
  Rect _selRect = Rect.zero;
  SelectionTransform _selTf = SelectionTransform.identity;

  /// Lineal: Kante, an der entlang gerade gezeichnet wird (Seiten-Koordinaten).
  (Offset, Offset)? _rulerEdge;

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
    final edge = _rulerEdge;
    // Am Lineal: auch die Vorhersage liegt auf der Kante.
    return edge == null ? p1 + ahead : _projectOnLine(p1 + ahead, edge.$1, edge.$2);
  }

  /// Schon gemalter Anfang des entstehenden Strichs (als fertiges Bild), damit
  /// pro Bild nur die neuen Teilstücke gemalt werden – auch bei langen Strichen.
  ui.Image? _cachedStart;
  int _cachedPoints = 0;
  double _dpr = 1;

  /// Wo das Bild des Anfangs liegt (Seiten-Koordinaten). Es ist nur so gross
  /// wie der Strich, und nur der sichtbare Teil – beim Zoomen wäre ein
  /// seitengrosses Bild sehr gross und jedes neue Aufnehmen teuer.
  Rect _cachedRect = Rect.zero;

  /// Sichtbarer Teil der Seite (beim Aufsetzen des Stifts bestimmt).
  Rect _visible = Rect.largest;

  void _resetCache() {
    _cachedStart?.dispose();
    _cachedStart = null;
    _cachedPoints = 0;
  }

  /// Sichtbarer Ausschnitt der Seite in ihren eigenen Koordinaten.
  Rect _visibleRect(Size size) {
    final box = context.findRenderObject() as RenderBox?;
    final page = Offset.zero & size;
    if (box == null || !box.attached) return page;
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    final corners = [
      box.globalToLocal(screen.topLeft),
      box.globalToLocal(screen.topRight),
      box.globalToLocal(screen.bottomLeft),
      box.globalToLocal(screen.bottomRight),
    ];
    var r = Rect.fromPoints(corners[0], corners[1]);
    for (final c in corners.skip(2)) {
      r = r.expandToInclude(Rect.fromPoints(c, c));
    }
    final v = r.intersect(page);
    return v.isEmpty ? page : v;
  }

  /// Bereich für das Bild des Anfangs: um die Punkte, mit Rand, nur sichtbar.
  Rect _cacheRectFor(List<InkPoint> pts, Size size, double pad) {
    var l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
    for (final p in pts) {
      l = math.min(l, p.x);
      r = math.max(r, p.x);
      t = math.min(t, p.y);
      b = math.max(b, p.y);
    }
    final bounds = Rect.fromLTRB(l * size.width, t * size.height, r * size.width, b * size.height).inflate(pad);
    final v = bounds.intersect(_visible);
    return v.isEmpty ? bounds : v;
  }

  InkController get c => widget.controller;
  ToolController get tools => widget.tools;

  /// Setzt die Bilder der Ebenen zu einem einzigen Bild zusammen.
  final _composer = _Composer();

  /// Für Tests: Bild eines Teils (`highlights` oder `layer/<id>`) und Reihenfolge.
  @visibleForTesting
  ui.Image? debugImageOf(String part) => _composer.parts[part]?._base;
  @visibleForTesting
  List<String> get debugOrder => _composer.order;

  @override
  void dispose() {
    _composer.dispose();
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
    if (tools.rulerPointers.contains(e.pointer)) return; // die Maus schiebt gerade das Lineal
    final eraserEvent = isEraserEvent(e);
    final mode = tools.mode;
    final instant = mode == ToolMode.read && e.kind == PointerDeviceKind.stylus && tools.instantPen;
    if (!eraserEvent && mode == ToolMode.stamp) {
      _beginStamp(e, size);
      return;
    }
    if (!eraserEvent && mode == ToolMode.lasso) {
      _beginLasso(e, size);
      return;
    }
    if (!eraserEvent && mode == ToolMode.move) {
      _beginMove(e, size);
      return;
    }
    if (!eraserEvent && mode == ToolMode.shape) {
      _pointer = e.pointer;
      _shapeStart = _shapeEnd = e.localPosition;
      tools.isDrawing.value = true;
      _activeRepaint.value++;
      return;
    }
    final drawing = mode == ToolMode.pen || mode == ToolMode.highlighter;
    if (!eraserEvent && !drawing && mode != ToolMode.eraser && !instant) return;
    _rulerEdge = !eraserEvent && mode != ToolMode.eraser ? _nearRulerEdge(e.position) : null;
    _visible = _visibleRect(size);
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
    if (_lasso != null || _selDrag != null) {
      _moveLasso(e.localPosition, size);
      return;
    }
    if (_stampPos != null) {
      _stampPos = e.localPosition - _stampGrab;
      _activeRepaint.value++;
      return;
    }
    if (_shapeStart != null) {
      _shapeEnd = e.localPosition;
      _activeRepaint.value++;
      return;
    }
    if (_provisional && (e.localPosition - _start).distance * tools.viewScale > kTouchSlop) {
      _provisional = false;
      tools.isDrawing.value = true;
    }
    _handle(e, size);
  }

  void _up(PointerEvent e, Size size) {
    if (e.pointer != _pointer) return;
    if (_lasso != null || _selDrag != null) {
      _endLasso(size);
      return;
    }
    if (_stampPos != null) {
      _endStamp(size);
      return;
    }
    if (_shapeStart != null) {
      _endShape(size);
      return;
    }
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
    _rulerEdge = null;
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
      var p = e.localPosition;
      final edge = _rulerEdge;
      if (edge != null) p = _projectOnLine(p, edge.$1, edge.$2);
      _points.add(InkPoint(p.dx / size.width, p.dy / size.height, normalizedPressure(e)));
    }
    _activeRepaint.value++;
  }

  // ---------------------------------------------------------------- Stempel
  void _beginStamp(PointerDownEvent e, Size size) {
    _pointer = e.pointer;
    final pos = e.localPosition;
    // Auf einen vorhandenen Stempel getippt → verschieben, sonst neu setzen.
    final hit = c.annotations
        .visibleStampsOn(widget.page)
        .reversed
        .where((s) => stampRect(s, size).inflate(8).contains(pos))
        .firstOrNull;
    if (hit != null) {
      _movingStampId = hit.id;
      final center = Offset(hit.x * size.width, hit.y * size.height);
      _stampGrab = pos - center;
      _stampPos = center;
    } else {
      _movingStampId = null;
      _stampGrab = Offset.zero;
      _stampPos = pos;
    }
    tools.isDrawing.value = true;
    _activeRepaint.value++;
  }

  void _endStamp(Size size) {
    final pos = _stampPos!;
    final x = (pos.dx / size.width).clamp(0.0, 1.0), y = (pos.dy / size.height).clamp(0.0, 1.0);
    final id = _movingStampId;
    if (id != null) {
      c.moveStamp(id, x, y);
    } else {
      final st = tools.stamp;
      c.addStamp(page: widget.page, x: x, y: y, glyph: st.glyph, size: st.size, color: st.color, custom: st.custom);
      if (st.custom == null) tools.rememberStamp(st.glyph);
    }
    _stampPos = null;
    _movingStampId = null;
    _pointer = null;
    tools.isDrawing.value = false;
    _activeRepaint.value++;
  }

  // ------------------------------------------------------------------ Lasso
  static const _selPad = 6.0;
  static const _handleRadius = 22.0;

  InkSelection? get _mySelection {
    final s = tools.selection.value;
    return s != null && s.isOn(c, widget.page) ? s : null;
  }

  /// Fläche der Auswahl in Pixeln (ohne Rand), null = nichts ausgewählt.
  Rect? selectionRect(SelectionIds ids, Size size) {
    final a = c.annotations;
    Rect? r;
    void add(Rect x) => r = r == null ? x : r!.expandToInclude(x);
    for (final id in ids.strokes) {
      final s = a[id];
      if (s == null || s.points.isEmpty) continue;
      final b = s.bounds;
      final half = s.width * size.width * 0.85;
      add(
        Rect.fromLTRB(
          b.left * size.width,
          b.top * size.height,
          b.right * size.width,
          b.bottom * size.height,
        ).inflate(half),
      );
    }
    for (final id in ids.stamps) {
      final st = a.stamp(id);
      if (st != null) add(stampRect(st, size));
    }
    for (final id in ids.texts) {
      final n = a.text(id);
      if (n == null) continue;
      final b = textNoteBounds(n, size);
      add(Rect.fromLTRB(b.left, b.top, b.right + 4, b.bottom)); // + Innenabstand der Notiz
    }
    return r;
  }

  void _beginLasso(PointerDownEvent e, Size size) {
    _pointer = e.pointer;
    final pos = e.localPosition;
    final sel = _mySelection;
    if (sel != null) {
      final r = selectionRect(sel.live, size);
      if (r != null) {
        final box = r.inflate(_selPad);
        if ((pos - box.bottomRight).distance <= _handleRadius) {
          _selDrag = _SelectDrag.scale;
        } else if (box.contains(pos)) {
          _selDrag = _SelectDrag.move;
        }
        if (_selDrag != null) {
          _selStart = pos;
          _selRect = r;
          _selTf = SelectionTransform.identity;
          tools.isDrawing.value = true;
          _activeRepaint.value++;
          return;
        }
      }
      tools.clearSelection(); // daneben getippt: Auswahl aufheben
    }
    _lasso = [pos];
    tools.isDrawing.value = true;
    _activeRepaint.value++;
  }

  /// Verschieben-Werkzeug: das oberste Element unter dem Stift anfassen.
  /// Es wird kurz zur Auswahl (so bewegt es sich flüssig mit) und nach dem
  /// Loslassen an der neuen Stelle abgelegt.
  void _beginMove(PointerDownEvent e, Size size) {
    final pos = e.localPosition;
    final ids = _elementAt(pos, size);
    if (ids == null) return;
    _pointer = e.pointer;
    _moving = true;
    final sel = InkSelection(c, widget.page, ids);
    tools.select(sel);
    final r = selectionRect(ids, size);
    if (r == null) {
      _pointer = null;
      _moving = false;
      tools.clearSelection();
      return;
    }
    _selDrag = _SelectDrag.move;
    _selStart = pos;
    _selRect = r;
    _selTf = SelectionTransform.identity;
    tools.isDrawing.value = true;
    _activeRepaint.value++;
  }

  /// Läuft gerade ein Verschieben mit dem Verschieben-Werkzeug?
  bool _moving = false;

  /// Oberstes sichtbares Element an [pos]: zuerst Text, dann Stempel, dann
  /// Striche (jüngste zuerst).
  SelectionIds? _elementAt(Offset pos, Size size) {
    final a = c.annotations;
    final tol = 10 / tools.viewScale;
    for (final n in a.visibleTextsOn(widget.page).toList().reversed) {
      final b = textNoteBounds(n, size);
      if (Rect.fromLTRB(b.left, b.top, b.right + 4, b.bottom).inflate(tol / 2).contains(pos)) {
        return SelectionIds(texts: {n.id});
      }
    }
    for (final st in a.visibleStampsOn(widget.page).toList().reversed) {
      if (stampRect(st, size).inflate(tol / 2).contains(pos)) return SelectionIds(stamps: {st.id});
    }
    final strokes = a.visibleStrokesOn(widget.page).toList()..sort((x, y) => y.createdAt.compareTo(x.createdAt));
    for (final s in strokes) {
      if (_touches(s, pos, tol, size)) return SelectionIds(strokes: {s.id});
    }
    return null;
  }

  void _moveLasso(Offset pos, Size size) {
    final lasso = _lasso;
    if (lasso != null) {
      if ((pos - lasso.last).distance >= 2) lasso.add(pos);
      _activeRepaint.value++;
      return;
    }
    final r = _selRect;
    final anchorNorm = Offset(r.left / size.width, r.top / size.height);
    if (_selDrag == _SelectDrag.move) {
      // Auf der Seite bleiben.
      final d = pos - _selStart;
      final dx = d.dx.clamp(-r.left, size.width - r.right);
      final dy = d.dy.clamp(-r.top, size.height - r.bottom);
      _selTf = SelectionTransform(delta: Offset(dx / size.width, dy / size.height), anchor: anchorNorm);
    } else {
      // Vergrössern am Griff unten rechts; die obere linke Ecke bleibt stehen.
      final v0 = r.bottomRight - r.topLeft;
      final len2 = v0.dx * v0.dx + v0.dy * v0.dy;
      if (len2 <= 0) return;
      final v = pos - r.topLeft;
      var s = (v.dx * v0.dx + v.dy * v0.dy) / len2;
      var maxS = 8.0;
      if (v0.dx > 0) maxS = math.min(maxS, (size.width - r.left) / v0.dx);
      if (v0.dy > 0) maxS = math.min(maxS, (size.height - r.top) / v0.dy);
      s = s.clamp(0.2, math.max(0.2, maxS));
      _selTf = SelectionTransform(scale: s, anchor: anchorNorm);
    }
    _activeRepaint.value++;
  }

  void _endLasso(Size size) {
    final lasso = _lasso;
    if (lasso != null) {
      var extent = 0.0;
      for (final p in lasso) {
        extent = math.max(extent, (p - lasso.first).distance);
      }
      if (lasso.length >= 3 && extent > 8 && tools.snippetMode) {
        _copySnippet(lasso, size);
      } else if (lasso.length >= 3 && extent > 8) {
        final poly = [for (final p in lasso) Offset(p.dx / size.width, p.dy / size.height)];
        final ids = lassoSelect(
          c.annotations,
          widget.page,
          poly,
          textBounds: (n) {
            final r = textNoteBounds(n, size);
            return Rect.fromLTRB(
              r.left / size.width,
              r.top / size.height,
              r.right / size.width,
              r.bottom / size.height,
            );
          },
        );
        tools.select(InkSelection(c, widget.page, ids));
      }
    } else {
      final sel = _mySelection;
      if (sel != null && !_selTf.isIdentity) c.transformSelection(sel.live, _selTf);
    }
    _lasso = null;
    _selDrag = null;
    _selTf = SelectionTransform.identity;
    _pointer = null;
    // Verschieben-Werkzeug: danach nichts ausgewählt lassen.
    if (_moving) {
      _moving = false;
      tools.clearSelection();
    }
    tools.isDrawing.value = false;
    _activeRepaint.value++;
  }

  /// Takte kopieren: das Rechteck um die Lasso-Linie als Bild (Noten samt
  /// Anmerkungen) in die Zwischenablage legen. Eingefügt wird es als eigener
  /// Stempel, den man verschieben und vergrössern kann.
  Future<void> _copySnippet(List<Offset> lasso, Size size) async {
    final page = widget.pageImage;
    final registry = CustomStamps.instance;
    if (page == null || registry == null) return;
    var r = Rect.fromPoints(lasso.first, lasso.first);
    for (final p in lasso) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    r = r.intersect(Offset.zero & size);
    if (r.width < 8 || r.height < 8) return;
    // In der Auflösung des Seitenbilds aufnehmen (scharf).
    final scale = page.width / size.width;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scale)
      ..translate(-r.left, -r.top);
    canvas.drawImageRect(
      page,
      Rect.fromLTWH(0, 0, page.width.toDouble(), page.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
    paintAnnotations(canvas, size, c.annotations, widget.page);
    final picture = recorder.endRecording();
    final img = await picture.toImage((r.width * scale).ceil(), (r.height * scale).ceil());
    picture.dispose();
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (png == null || !mounted) return;
    final s = await registry.add(
      name: tr('Notenausschnitt', 'Music excerpt'),
      png: png.buffer.asUint8List(),
      anchorX: 0.5,
      anchorY: 0.5,
      aspect: r.width / r.height,
      snippet: true,
    );
    final stamp = Stamp(
      id: 'clip',
      page: widget.page,
      x: r.center.dx / size.width,
      y: r.center.dy / size.height,
      glyph: 0,
      size: r.height / size.width,
      color: 0xFF000000,
      createdAt: DateTime.now().toUtc(),
      custom: s.id,
    );
    tools.putOnClipboard(InkClip(stamps: [stamp]), InkSelection(c, widget.page, const SelectionIds()));
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Takte kopiert – jetzt eine Seite antippen und «Einfügen» (Strg+V).',
              'Bars copied – now tap a page and «Paste» (Ctrl+V).',
            ),
          ),
        ),
      );
    }
  }

  // ----------------------------------------------------------------- Formen
  void _endShape(Size size) {
    final a = _shapeStart!, b = _shapeEnd!;
    final style = tools.shape;
    final pieces = shapeGeometry(tools.shapeKind, a, b, style.width * size.width, pageWidth: size.width);
    if (pieces.isNotEmpty && (b - a).distance > 6) {
      c.beginBatch(); // eine Form = ein Rückgängig-Schritt
      for (final piece in pieces) {
        final look = _shapeLook(piece);
        c.addStroke(
          page: widget.page,
          tool: InkTool.pen,
          color: look.color,
          width: style.width * piece.widthFactor,
          fill: look.fill,
          points: [for (final p in piece.points) InkPoint(p.dx / size.width, p.dy / size.height, 0.5)],
        );
      }
      c.endBatch();
    }
    _shapeStart = _shapeEnd = null;
    _pointer = null;
    tools.isDrawing.value = false;
    _activeRepaint.value++;
  }

  /// Farbe von Rand und Fläche eines Teils einer Form.
  ({int color, int? fill}) _shapeLook(ShapePiece piece) {
    final color = tools.shape.color;
    if (piece.solid) return (color: color, fill: color);
    final fill = piece.closed && tools.shapeFill != 0 ? tools.shapeFill : null;
    // Ohne Rand: Rand in der Füllfarbe (so bleiben Radieren und Auswählen gleich).
    return (color: fill != null && !tools.shapeOutline ? fill : color, fill: fill);
  }

  // ----------------------------------------------------------------- Lineal
  /// Liegt der Stift nahe an einer Kante des Lineals? Dann wird an dieser
  /// Kante entlang gezeichnet (gerade Linie).
  (Offset, Offset)? _nearRulerEdge(Offset global) {
    if (!tools.rulerVisible || tools.rulerCenter == null) return null;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final c0 = tools.rulerCenter!, a = tools.rulerAngle;
    final u = Offset(math.cos(a), math.sin(a)), n = Offset(-math.sin(a), math.cos(a));
    final half = tools.rulerLength / 2;
    const thick = ToolController.rulerThickness / 2;
    final rel = global - c0;
    final along = rel.dx * u.dx + rel.dy * u.dy;
    final across = rel.dx * n.dx + rel.dy * n.dy;
    if (along.abs() > half + 20) return null;
    // Innerhalb der oberen bzw. unteren Hälfte oder bis 36 px ausserhalb.
    if (across.abs() > thick + 36) return null;
    final side = across >= 0 ? 1.0 : -1.0;
    final edgeOffset = n * ((thick + 2) * side);
    final p0 = box.globalToLocal(c0 - u * (half + 400) + edgeOffset);
    final p1 = box.globalToLocal(c0 + u * (half + 400) + edgeOffset);
    return (p0, p1);
  }

  static Offset _projectOnLine(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return a;
    final t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2;
    return a + ab * t;
  }

  /// Ganze Elemente: kleiner, fester Fangradius. Teilweise: gewählte Grösse.
  double get eraserRadius => (tools.eraserPartial ? tools.eraserRadius : 10) / tools.viewScale;

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
    // Stempel werden immer ganz gelöscht.
    final stampHits = c.annotations.visibleStampsOn(widget.page).where((st) => stampRect(st, size).overlaps(eraser));
    if (stampHits.isNotEmpty) c.deleteStamps(stampHits.toList());
  }

  /// Schnelle Vorprüfung über das umgebende Rechteck, dann genau.
  bool _touches(Stroke s, Offset pos, double r, Size size) {
    final half = s.width * size.width / 2;
    final b = s.bounds;
    final box = Rect.fromLTRB(b.left * size.width, b.top * size.height, b.right * size.width, b.bottom * size.height);
    if (!box.inflate(r + half * 1.7).contains(pos)) return false;
    // Gefüllte Form: auch innen getroffen.
    if (s.fill != null && s.points.length >= 3) {
      final area = Path()..addPolygon([for (final p in s.points) Offset(p.x * size.width, p.y * size.height)], true);
      if (area.contains(pos)) return true;
    }
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
    // Gefüllte Formen nicht zerschneiden (die Fläche würde sonst zerfallen).
    if (s.fill != null) {
      c.eraseStrokes([s]);
      return;
    }
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
              // Pro Ebene ein eigenes Bild: Zeichnen auf einer Ebene malt nur
              // deren Bild weiter, Ein-/Ausblenden geht sofort.
              ListenableBuilder(
                listenable: Listenable.merge([c, tools.selection]),
                builder: (context, _) {
                  final sel = tools.selection.value;
                  // Ausgewähltes malt die Auswahl-Ebene (damit es sich mitbewegt).
                  final hidden = sel != null && sel.isOn(c, widget.page)
                      ? {...sel.ids.strokes, ...sel.ids.stamps}
                      : const <String>{};
                  final parts = <Widget>[
                    // Leuchtstift immer zuunterst – hinter allem anderen,
                    // auf allen Ebenen (jeder Strich bleibt auf seiner Ebene).
                    _StrokesImage(
                      key: const ValueKey('highlights'),
                      composer: _composer,
                      partKey: 'highlights',
                      controller: c,
                      page: widget.page,
                      layer: null,
                      highlights: true,
                      background: widget.pageImage,
                      size: size,
                      hidden: hidden,
                    ),
                    for (final l in c.annotations.layers)
                      if (!l.isGroup && c.annotations.isLayerShown(l.id))
                        _StrokesImage(
                          key: ValueKey('layer/${l.id}'),
                          composer: _composer,
                          partKey: 'layer/${l.id}',
                          controller: c,
                          page: widget.page,
                          layer: l.id,
                          size: size,
                          hidden: hidden,
                        ),
                  ];
                  _composer.order = [for (final w in parts) (w as _StrokesImage).partKey];
                  _composer.pageImage = widget.pageImage;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // Die Ebenen-Bilder selbst sind unsichtbar; gezeigt wird
                      // ein einziges zusammengesetztes Bild (siehe _Composer).
                      ...parts,
                      RepaintBoundary(child: CustomPaint(painter: _CompositePainter(_composer))),
                    ],
                  );
                },
              ),
              RepaintBoundary(
                child: CustomPaint(
                  painter: _SelectionPainter(this, repaint: Listenable.merge([_activeRepaint, tools.selection, c])),
                ),
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

/// Fertige Striche und Stempel einer Seite, vorgerendert als Bild.
///
/// Damit das Schreiben auch auf vollen Seiten flüssig bleibt:
/// * Kommt nur etwas **dazu** (der Normalfall beim Schreiben), wird das
///   bestehende Bild genommen und nur das Neue darübergemalt. Bis das neue
///   Bild fertig ist (ein, zwei Bilder lang), wird das Neue direkt gemalt.
/// * Nur wenn etwas verschwindet oder sich ändert (Radieren, Rückgängig,
///   Abgleich), wird die ganze Seite neu erzeugt.
/// * Meldet der Controller etwas, das diese Seite nicht betrifft (Speichern,
///   andere Seite, Text), passiert gar nichts.
class _StrokesImage extends StatefulWidget {
  const _StrokesImage({
    super.key,
    required this.composer,
    required this.partKey,
    required this.controller,
    required this.page,
    required this.size,
    this.layer = kDefaultLayer,
    this.highlights = false,
    this.background,
    this.hidden = const {},
  });
  final _Composer composer;
  final String partKey;
  final InkController controller;
  final int page;
  final Size size;

  /// Nur Elemente dieser Ebene (null = alle eingeblendeten Ebenen).
  final String? layer;

  /// true: nur Leuchtstift-Striche. false: alles ausser Leuchtstift.
  final bool highlights;

  /// Nur beim Leuchtstift: Notenseite, mit der er fest verrechnet wird.
  final ui.Image? background;

  /// Nicht malen (gerade ausgewählt).
  final Set<String> hidden;

  @override
  State<_StrokesImage> createState() => _StrokesImageState();
}

class _StrokesImageState extends State<_StrokesImage> {
  /// Fertiges Bild (null = leer) und welche Elemente darin stecken.
  ui.Image? _base;
  List<String> _baseKeys = const [];
  Size? _baseSize;
  double? _baseDpr;

  /// Neu hinzugekommene Elemente, die (noch) nicht im Bild sind.
  List<Object> _pending = const [];

  bool _dirty = true;
  bool _composing = false;

  /// Leuchtstift-Bild enthält schon die Notenseite (dann normal anzeigen).
  bool _withBackground = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    CustomStamps.instance?.addListener(_onCustomStamps);
    widget.composer.parts[widget.partKey] = this;
  }

  /// Ein eigenes Stempel-Bild ist (nach)geladen oder geändert → neu malen.
  void _onCustomStamps() {
    if (!mounted) return;
    setState(() {
      _baseSize = null;
      _dirty = true;
    });
  }

  @override
  void didUpdateWidget(_StrokesImage old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
      _baseSize = null; // ganz neu erzeugen
      _dirty = true;
    }
    if (old.page != widget.page || old.layer != widget.layer || old.highlights != widget.highlights) {
      _baseSize = null;
      _dirty = true;
    }
    if (!setEquals(old.hidden, widget.hidden)) _dirty = true;
    if (!identical(old.background, widget.background)) {
      _baseSize = null; // mit der neuen Notenseite ganz neu verrechnen
      _dirty = true;
    }
  }

  void _onChanged() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _composeTimer?.cancel();
    widget.controller.removeListener(_onChanged);
    CustomStamps.instance?.removeListener(_onCustomStamps);
    if (identical(widget.composer.parts[widget.partKey], this)) {
      widget.composer.parts.remove(widget.partKey);
      widget.composer.changed();
    }
    _generation++;
    // Erst nach dem nächsten Bild freigeben (das zusammengesetzte Bild
    // könnte es in diesem Bild noch malen).
    final b = _base;
    if (b != null) WidgetsBinding.instance.addPostFrameCallback((_) => b.dispose());
    super.dispose();
  }

  /// Sichtbare Elemente der Seite in Malreihenfolge (älteste zuerst).
  List<Object> _items() {
    final a = widget.controller.annotations;
    final hidden = widget.hidden;
    final layer = widget.layer;
    final hl = widget.highlights;
    bool onLayer(String? l) => layer == null || a.resolveLayer(l) == layer;
    final items = <Object>[
      ...a
          .visibleStrokesOn(widget.page)
          .where((s) => !hidden.contains(s.id) && onLayer(s.layer) && (s.tool == InkTool.highlighter) == hl),
      if (!hl) ...a.visibleStampsOn(widget.page).where((s) => !hidden.contains(s.id) && onLayer(s.layer)),
    ];
    items.sort((x, y) {
      final c = _created(x).compareTo(_created(y));
      return c != 0 ? c : _id(x).compareTo(_id(y));
    });
    return items;
  }

  static DateTime _created(Object o) => o is Stroke ? o.createdAt : (o as Stamp).createdAt;
  static String _id(Object o) => o is Stroke ? o.id : (o as Stamp).id;
  static String _keyOf(Object o) => o is Stroke
      ? '${o.id}@${o.lastChange.microsecondsSinceEpoch}'
      : '${(o as Stamp).id}@${o.lastChange.microsecondsSinceEpoch}';

  static bool _startsWith(List<String> list, List<String> prefix) {
    if (prefix.length > list.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (list[i] != prefix[i]) return false;
    }
    return true;
  }

  static void _paintItems(Canvas canvas, Size size, Iterable<Object> items, {bool multiply = true}) {
    for (final it in items) {
      if (it is Stroke) {
        paintStroke(canvas, size, it.tool, Color(it.color), it.width, it.points, multiply: multiply, fill: it.fill);
      } else if (it is Stamp) {
        paintStamp(canvas, size, it);
      }
    }
  }

  /// Bild aus [base] (in Pixeln) plus [items] aufnehmen.
  ///
  /// [multiply]: Leuchtstift im Bild "multiplizieren". Im eigenen
  /// Leuchtstift-Bild nicht: Dort gibt es nichts darunter (manche Grafikkarten
  /// zeigen dann gar nichts), das ganze Bild wird stattdessen beim Anzeigen
  /// mit den Noten multipliziert.
  static ui.Picture _record(
    ui.Image? base,
    Iterable<Object> items,
    Size size,
    double dpr, {
    bool multiply = true,
    ui.Image? background,
  }) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (base != null) {
      canvas.drawImage(base, Offset.zero, Paint());
    } else if (background != null) {
      // Notenseite als Grund: Der Leuchtstift wird darauf multipliziert und
      // das Ergebnis ist ein fertiges, deckendes Bild.
      canvas.drawImageRect(
        background,
        Rect.fromLTWH(0, 0, background.width.toDouble(), background.height.toDouble()),
        Rect.fromLTWH(0, 0, size.width * dpr, size.height * dpr),
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    canvas.scale(dpr);
    _paintItems(canvas, size, items, multiply: multiply);
    return recorder.endRecording();
  }

  void _setBase(ui.Image? img, List<String> keys, Size size, double dpr) {
    final old = _base;
    _base = img;
    _baseKeys = keys;
    _baseSize = size;
    _baseDpr = dpr;
    // Das alte Bild erst nach dem nächsten Bild freigeben.
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  void _update(double dpr) {
    _dirty = false;
    final size = widget.size;
    final items = _items();
    final keys = [for (final it in items) _keyOf(it)];

    if (_baseSize == size && _baseDpr == dpr && _startsWith(keys, _baseKeys)) {
      // Nichts verschwunden: höchstens etwas dazugekommen.
      _pending = items.sublist(_baseKeys.length);
      if (_pending.isNotEmpty) _composeSoon(dpr);
      return;
    }
    _composeTimer?.cancel();

    // Etwas ist verschwunden oder hat sich verändert → ganz neu erzeugen.
    _generation++;
    _pending = const [];
    final bg = widget.highlights ? widget.background : null;
    // Das Leuchtstift-Bild enthält immer die Notenseite (auch ohne Leuchtstift),
    // damit pro Seite am Ende nur ein einziges Bild gezeigt werden muss.
    if ((items.isEmpty && bg == null) || size.isEmpty) {
      _setBase(null, keys, size, dpr);
      return;
    }
    _withBackground = bg != null;
    final picture = _record(null, items, size, dpr, multiply: !widget.highlights || bg != null, background: bg);
    final img = picture.toImageSync((size.width * dpr).ceil(), (size.height * dpr).ceil());
    picture.dispose();
    _setBase(img, keys, size, dpr);
  }

  /// Neue Elemente erst ins Bild nehmen, wenn kurz nichts mehr dazukommt.
  ///
  /// Beim Schreiben (viele kurze Striche) würde sonst nach jedem Strich die
  /// ganze Seite neu aufgenommen – im Zoom ist das Bild gross, das bremst
  /// (gemessen: 11 statt 31 Bilder/s). Bis dahin malt der _CompositePainter
  /// die neuen Elemente direkt; man sieht keinen Unterschied.
  Timer? _composeTimer;
  int _timedPending = 0;

  void _composeSoon(double dpr) {
    if (_pending.length >= 40) {
      _composeTimer?.cancel();
      _compose(dpr);
      return;
    }
    // Nur wenn wirklich etwas dazukam, wieder warten (ein blosses Neu-Aufbauen,
    // z. B. nach dem Speichern, schiebt das Einsortieren nicht hinaus).
    if (_composeTimer?.isActive == true && _pending.length == _timedPending) return;
    _composeTimer?.cancel();
    _timedPending = _pending.length;
    _composeTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _compose(dpr);
    });
  }

  /// Bestehendes Bild + neue Elemente zu einem neuen Bild zusammenfügen.
  ///
  /// Bewusst `toImage` (im Hintergrund) statt `toImageSync`: Das fertige Bild
  /// hängt dann nicht mehr am vorherigen. Sonst würde jeder Strich alle
  /// früheren Bilder im Speicher festhalten.
  Future<void> _compose(double dpr) async {
    if (_composing) return; // Nach dem Fertigwerden wird nochmals geprüft.
    _composing = true;
    final gen = _generation;
    final size = _baseSize!;
    final pending = _pending;
    final keys = [..._baseKeys, for (final it in pending) _keyOf(it)];
    late final ui.Image img;
    try {
      final picture = _record(_base, pending, size, dpr, multiply: !widget.highlights || _withBackground);
      img = await picture.toImage((size.width * dpr).ceil(), (size.height * dpr).ceil());
      picture.dispose();
    } finally {
      _composing = false;
    }
    if (!mounted || gen != _generation) {
      img.dispose();
      if (mounted) setState(() => _dirty = true);
      return;
    }
    setState(() {
      _setBase(img, keys, size, dpr);
      _dirty = true; // inzwischen Dazugekommenes einsortieren
    });
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (_dirty || _baseSize != widget.size || _baseDpr != dpr) _update(dpr);
    // Nicht selbst malen – der _CompositePainter zeigt alles zusammen.
    widget.composer.parts[widget.partKey] = this;
    widget.composer.changed();
    return const SizedBox.shrink();
  }
}

/// Setzt die Bilder aller Ebenen einer Seite zu **einem** Bild zusammen.
///
/// Gemessen: Bei jedem Bild bis zu sechs seitengrosse Bilder übereinander zu
/// legen (Leuchtstift + Ebenen, bei zwei Seiten doppelt), kostet auf dem
/// Surface viel Zeit. Darum wird daraus ein Bild gemacht, sobald sich etwas
/// geändert hat. Bis es fertig ist (ein, zwei Bilder lang), werden die
/// Einzelbilder gezeigt – nie etwas Falsches.
class _Composer extends ChangeNotifier {
  final Map<String, _StrokesImageState> parts = {};
  List<String> order = const [];

  /// Notenseite – gemalt, solange sie noch in keinem Bild steckt.
  ui.Image? pageImage;

  /// Steckt die Notenseite schon im Leuchtstift-Bild?
  bool get pageIncluded => ordered.any((p) => p.widget.highlights && p._base != null && p._withBackground);

  ui.Image? _composite;
  List<ui.Image> _compositeOf = const [];
  bool _composing = false;
  bool _disposed = false;

  List<_StrokesImageState> get ordered => [for (final k in order) ?parts[k]];

  void changed() {
    if (!_disposed) notifyListeners();
  }

  /// Bilder, die gerade gezeigt werden müssen (unten zuerst).
  List<ui.Image> currentBases() => [for (final p in ordered) ?p._base];

  /// Kann zusammengesetzt werden? Ein Leuchtstift-Bild ohne Notenseite muss
  /// beim Anzeigen multipliziert werden – das geht nicht in einem fertigen Bild.
  bool get _composable => ordered.every((p) => !(p.widget.highlights && p._base != null && !p._withBackground));

  ui.Image? compositeFor(List<ui.Image> bases) {
    final c = _composite;
    if (c == null || bases.length != _compositeOf.length) return null;
    for (var i = 0; i < bases.length; i++) {
      if (!identical(bases[i], _compositeOf[i])) return null;
    }
    return c;
  }

  /// Im Hintergrund ein neues Gesamtbild erzeugen.
  void schedule(List<ui.Image> bases, Size size) {
    if (_composing || bases.length < 2 || !_composable || size.isEmpty) return;
    _composing = true;
    final w = bases.first.width, h = bases.first.height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final dst = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    for (final b in bases) {
      canvas.drawImageRect(b, Rect.fromLTWH(0, 0, b.width.toDouble(), b.height.toDouble()), dst, Paint());
    }
    final picture = recorder.endRecording();
    picture.toImage(w, h).then((img) {
      picture.dispose();
      _composing = false;
      if (_disposed) {
        img.dispose();
        return;
      }
      final old = _composite;
      _composite = img;
      _compositeOf = bases;
      if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    final c = _composite;
    if (c != null) WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    super.dispose();
  }
}

/// Malt das Gesamtbild – oder, solange es noch entsteht, die Einzelbilder –
/// und darüber die neuen Elemente, die noch in keinem Bild sind.
class _CompositePainter extends CustomPainter {
  _CompositePainter(this.composer) : super(repaint: composer);
  final _Composer composer;

  @override
  void paint(Canvas canvas, Size size) {
    final parts = composer.ordered;
    final bases = composer.currentBases();
    final dst = Offset.zero & size;
    final composite = bases.length < 2 ? null : composer.compositeFor(bases);
    final page = composer.pageImage;
    if (!composer.pageIncluded && page != null) _draw(canvas, page, dst, Paint()..filterQuality = FilterQuality.medium);
    if (composite != null) {
      _draw(canvas, composite, dst, Paint());
    } else {
      for (final p in parts) {
        final b = p._base;
        if (b == null) continue;
        final multiply = p.widget.highlights && !p._withBackground;
        // Wie ein echter Leuchtstift: schwarze Noten darunter bleiben schwarz.
        _draw(canvas, b, dst, Paint()..blendMode = multiply ? BlendMode.multiply : BlendMode.srcOver);
      }
      composer.schedule(bases, size);
    }
    for (final p in parts) {
      if (p._pending.isNotEmpty) _StrokesImageState._paintItems(canvas, size, p._pending);
    }
  }

  static void _draw(Canvas canvas, ui.Image img, Rect dst, Paint paint) => canvas.drawImageRect(
    img,
    Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    dst,
    paint.filterQuality == FilterQuality.medium ? paint : (paint..filterQuality = FilterQuality.none),
  );

  @override
  bool shouldRepaint(_CompositePainter old) => !identical(old.composer, composer);
}

enum _SelectDrag { move, scale }

/// Lasso-Linie und Auswahl: Rahmen, Griff und die ausgewählten Elemente
/// (beim Verschieben/Vergrössern gleich an der neuen Stelle).
class _SelectionPainter extends CustomPainter {
  _SelectionPainter(this.state, {required Listenable repaint}) : super(repaint: repaint);
  final _InkLayerState state;

  static final _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = VoltiColors.selection;

  @override
  void paint(Canvas canvas, Size size) {
    final lasso = state._lasso;
    if (lasso != null && lasso.length > 1) {
      final path = Path()..addPolygon(lasso, true);
      canvas.drawPath(path, Paint()..color = VoltiColors.selection.withValues(alpha: 0.10));
      _dashedPath(canvas, lasso, close: false);
    }
    final sel = state._mySelection;
    if (sel == null) return;
    final ids = sel.live;
    final r = state.selectionRect(ids, size);
    if (r == null) return;
    final tf = state._selTf;
    final a = Offset(tf.anchor.dx * size.width, tf.anchor.dy * size.height);
    final d = Offset(tf.delta.dx * size.width, tf.delta.dy * size.height);
    Offset px(Offset p) => a + (p - a) * tf.scale + d;

    // Ausgewählte Elemente
    final ann = state.c.annotations;
    canvas.save();
    canvas.translate(a.dx + d.dx, a.dy + d.dy);
    canvas.scale(tf.scale);
    canvas.translate(-a.dx, -a.dy);
    final strokes = [for (final id in ids.strokes) ?ann[id]]..sort((x, y) => x.createdAt.compareTo(y.createdAt));
    for (final s in strokes) {
      paintStroke(canvas, size, s.tool, Color(s.color), s.width, s.points, fill: s.fill);
    }
    for (final id in ids.stamps) {
      final st = ann.stamp(id);
      if (st != null) paintStamp(canvas, size, st);
    }
    canvas.restore();
    // Text-Notizen in ihrer neuen Grösse (nicht nur vergrössert gemalt).
    final scaled = Size(size.width * tf.scale, size.height * tf.scale);
    for (final id in ids.texts) {
      final n = ann.text(id);
      if (n == null) continue;
      final o = px(Offset(n.x * size.width, n.y * size.height));
      canvas.save();
      canvas.translate(o.dx - n.x * scaled.width, o.dy - n.y * scaled.height);
      paintTextNote(canvas, n, scaled);
      canvas.restore();
    }

    // Rahmen und Griff
    final box = Rect.fromPoints(px(r.topLeft), px(r.bottomRight)).inflate(_InkLayerState._selPad);
    canvas.drawRect(box, Paint()..color = VoltiColors.selection.withValues(alpha: 0.08));
    _dashedPath(canvas, [box.topLeft, box.topRight, box.bottomRight, box.bottomLeft], close: true);
    final h = box.bottomRight;
    canvas.drawCircle(h, 9, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(h, 9, _line..strokeWidth = 2);
    // kleiner Doppelpfeil im Griff
    final arrow = Paint()
      ..color = VoltiColors.selection
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(h + const Offset(-4, -4), h + const Offset(4, 4), arrow);
    canvas.drawLine(h + const Offset(4, 4), h + const Offset(0.5, 4), arrow);
    canvas.drawLine(h + const Offset(4, 4), h + const Offset(4, 0.5), arrow);
    canvas.drawLine(h + const Offset(-4, -4), h + const Offset(-0.5, -4), arrow);
    canvas.drawLine(h + const Offset(-4, -4), h + const Offset(-4, -0.5), arrow);
    _line.strokeWidth = 1.5;
  }

  /// Gestrichelte Linie durch [pts].
  static void _dashedPath(Canvas canvas, List<Offset> pts, {required bool close}) {
    const dash = 6.0, gap = 4.0;
    final all = close ? [...pts, pts.first] : pts;
    var on = true;
    var left = dash;
    for (var i = 1; i < all.length; i++) {
      var a = all[i - 1];
      final b = all[i];
      var seg = (b - a).distance;
      if (seg == 0) continue;
      final dir = (b - a) / seg;
      while (seg > 0) {
        final step = math.min(left, seg);
        final next = a + dir * step;
        if (on) canvas.drawLine(a, next, _line);
        a = next;
        seg -= step;
        left -= step;
        if (left <= 0) {
          on = !on;
          left = on ? dash : gap;
        }
      }
    }
  }

  @override
  bool shouldRepaint(_SelectionPainter old) => true;
}

/// Zeichnet fertige Striche einer Seite.
class StrokesPainter extends CustomPainter {
  StrokesPainter(this.strokes);
  final List<Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      paintStroke(canvas, size, s.tool, Color(s.color), s.width, s.points, fill: s.fill);
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
    final tools = state.tools;
    // Stempel: Vorschau an der Stiftposition.
    final stampPos = state._stampPos;
    if (stampPos != null) {
      final moving = state._movingStampId == null ? null : state.c.annotations.stamp(state._movingStampId!);
      final glyph = moving?.glyph ?? tools.stamp.glyph;
      final custom = moving == null ? tools.stamp.custom : moving.custom;
      final fs = (moving?.size ?? tools.stamp.size) * size.width;
      final color = Color(moving?.color ?? tools.stamp.color);
      if (custom != null) {
        paintCustomStamp(canvas, custom, stampPos, fs, opacity: 0.75);
      } else {
        paintGlyph(canvas, glyph, stampPos, fs, color.withValues(alpha: color.a * 0.75));
      }
      return;
    }
    // Form: Vorschau beim Aufziehen.
    final a = state._shapeStart, b = state._shapeEnd;
    if (a != null && b != null) {
      final style = tools.shape;
      final paint = Paint()
        ..color = Color(style.color)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, style.width * size.width)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final piece in shapeGeometry(tools.shapeKind, a, b, style.width * size.width, pageWidth: size.width)) {
        final look = state._shapeLook(piece);
        if (look.fill != null) {
          canvas.drawPath(Path()..addPolygon(piece.points, true), Paint()..color = Color(look.fill!));
        }
        paint
          ..color = Color(look.color)
          ..strokeWidth = math.max(0.8, style.width * piece.widthFactor * size.width);
        canvas.drawPoints(ui.PointMode.polygon, piece.points, paint);
      }
      return;
    }
    if (state._erasing) {
      final pos = state._eraserPos;
      if (pos != null) {
        canvas.drawCircle(
          pos,
          state.eraserRadius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = VoltiColors.selection.withValues(alpha: 0.6),
        );
      }
      return;
    }
    final preset = state._preset;
    final pts = state._points;
    if (pts.isEmpty || preset == null || state._provisional) return;
    PerfMeter.instance.recordStrokeFrame(state._lastEventTime);

    // Den Anfang des Strichs als fertiges Bild wiederverwenden und pro Bild
    // nur die neuen Teilstücke malen. Leuchtstift und halbtransparente Stifte
    // werden dafür in voller Farbe gemalt und als Ganzes durchsichtig gemacht
    // (sonst wären die Übergänge sichtbar) – nie als durchsichtige Fläche, die
    // bei jedem Bild ganz neu berechnet werden müsste (gemessen: sehr langsam).
    final color = Color(preset.color);
    final hl = preset.tool == InkTool.highlighter;
    final translucent = hl || color.a < 1.0;
    final solid = color.withValues(alpha: 1);
    void segments(Canvas c, int from, int to) => hl
        ? paintHighlighterSegments(c, size, solid, preset.width, pts, from, to)
        : paintPenSegments(c, size, solid, preset.width, pts, from, to);
    if (pts.length < 2) {
      paintStroke(canvas, size, preset.tool, color, preset.width, pts, multiply: false);
      return;
    }
    final dpr = state._dpr;
    final dst = Offset.zero & size;
    if (hl) {
      _paintHighlighter(canvas, size, color, preset.width, pts, dpr, dst);
      return;
    }
    if (pts.length - state._cachedPoints > 24) {
      // Ganz neu aufnehmen (ohne das vorige Bild hineinzumalen): So hält das
      // neue Bild nicht alle früheren im Speicher fest.
      _recordCache(size, dpr, preset.width * size.width * 2 + 2, (c) => segments(c, 1, pts.length));
    }
    if (translucent) {
      // Nur so gross wie der Strich (spart Arbeit beim Durchsichtig-Machen).
      var l = double.infinity, tp = double.infinity, r = -double.infinity, b = -double.infinity;
      for (final p in pts) {
        l = math.min(l, p.x);
        r = math.max(r, p.x);
        tp = math.min(tp, p.y);
        b = math.max(b, p.y);
      }
      final pad = preset.width * size.width * 2 + 2;
      final bounds = Rect.fromLTRB(l * size.width, tp * size.height, r * size.width, b * size.height).inflate(pad);
      canvas.saveLayer(bounds, Paint()..color = Color.fromRGBO(0, 0, 0, color.a));
    }
    final img = state._cachedStart;
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        state._cachedRect,
        Paint(),
      );
    }
    segments(canvas, img == null ? 1 : state._cachedPoints, pts.length);
    if (!hl) _paintPrediction(canvas, size, preset.copyWith(color: solid.toARGB32()), pts);
    if (translucent) canvas.restore();
  }

  /// Entstehender Leuchtstift – ohne Zwischenbild pro Bild (`saveLayer`), das
  /// auf vielen Grafikchips teuer ist (gemessen auf dem Surface: 14 Bilder/s).
  ///
  /// * Der Anfang liegt als Bild in voller Farbe vor und wird mit der
  ///   Deckkraft des Leuchtstifts gemalt (ein einziges Bild, günstig).
  /// * Das neue Stück wird als *ein* durchsichtiger Linienzug gemalt – in
  ///   sich überlappt nichts doppelt.
  /// * Beide Teile enden gerade ("butt") und stossen genau aneinander, also
  ///   gibt es am Übergang keine dunklere Stelle.
  void _paintHighlighter(
    Canvas canvas,
    Size size,
    Color color,
    double width,
    List<InkPoint> pts,
    double dpr,
    Rect dst,
  ) {
    Path pathOf(int from, int to) {
      final path = Path()..moveTo(pts[from].x * size.width, pts[from].y * size.height);
      for (var i = from + 1; i < to; i++) {
        path.lineTo(pts[i].x * size.width, pts[i].y * size.height);
      }
      return path;
    }

    Paint paintFor(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * size.width
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.round
      ..color = c;

    if (pts.length - state._cachedPoints > 32) {
      final full = paintFor(color.withValues(alpha: 1));
      _recordCache(size, dpr, width * size.width + 2, (c) => c.drawPath(pathOf(0, pts.length), full));
    }
    final img = state._cachedStart;
    final from = img == null ? 0 : state._cachedPoints - 1;
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        state._cachedRect,
        Paint()..color = Color.fromRGBO(0, 0, 0, color.a),
      );
    }
    if (pts.length - from >= 2) canvas.drawPath(pathOf(from, pts.length), paintFor(color));
  }

  /// Den bisherigen Strich als Bild aufnehmen – nur so gross wie er selbst
  /// (und nur der sichtbare Teil), in der Auflösung des Bildschirms.
  void _recordCache(Size size, double dpr, double pad, void Function(Canvas) paint) {
    final rect = state._cacheRectFor(state._points, size, pad);
    final w = (rect.width * dpr).ceil(), h = (rect.height * dpr).ceil();
    if (w <= 0 || h <= 0) return;
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder)
      ..scale(dpr)
      ..translate(-rect.left, -rect.top);
    paint(c);
    final picture = recorder.endRecording();
    final img = picture.toImageSync(w, h);
    picture.dispose();
    final old = state._cachedStart;
    state._cachedStart = img;
    state._cachedRect = Rect.fromLTWH(rect.left, rect.top, w / dpr, h / dpr);
    state._cachedPoints = state._points.length;
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
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
void paintStroke(
  Canvas canvas,
  Size size,
  InkTool tool,
  Color color,
  double width,
  List<InkPoint> pts, {
  bool multiply = true,
  int? fill,
}) {
  if (pts.isEmpty) return;
  final w = width * size.width;
  Offset at(InkPoint p) => Offset(p.x * size.width, p.y * size.height);
  // Gefüllte Form (Rechteck, Ellipse, Pfeilspitze): zuerst die Fläche.
  if (fill != null && pts.length >= 3) {
    canvas.drawPath(Path()..addPolygon([for (final p in pts) at(p)], true), Paint()..color = Color(fill));
  }

  if (tool == InkTool.highlighter) {
    final path = Path()..moveTo(at(pts.first).dx, at(pts.first).dy);
    for (final p in pts.skip(1)) {
      path.lineTo(at(p).dx, at(p).dy);
    }
    if (pts.length == 1) path.lineTo(at(pts.first).dx + 0.1, at(pts.first).dy);
    // Ganz gerade Striche (am Lineal) haben eine Umrandung ohne Höhe bzw.
    // Breite. Manche Grafikkarten lassen solche Formen beim Malen ins
    // Seitenbild einfach weg (beim Besitzer verschwanden Lineal-Striche
    // nach dem Loslassen). Ein winziger, unsichtbarer Versatz verhindert das.
    final b = path.getBounds();
    if (b.height < 0.05 || b.width < 0.05) {
      final e = at(pts.last);
      path.lineTo(e.dx + (b.width < 0.05 ? 0.05 : 0), e.dy + (b.height < 0.05 ? 0.05 : 0));
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.square
        ..strokeJoin = StrokeJoin.round
        ..blendMode = multiply ? BlendMode.multiply : BlendMode.srcOver
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
  } else if (pts.every((p) => p.pressure == pts.first.pressure)) {
    // Gleichmässiger Druck (Lineal, Formen): in einem Zug malen. Einzelne
    // Teilstücke überlappen sich an den Enden, bei dünnen Linien sieht man
    // dort sonst dunklere Pünktchen.
    final path = Path()..moveTo(at(pts.first).dx, at(pts.first).dy);
    for (final p in pts.skip(1)) {
      path.lineTo(at(p).dx, at(p).dy);
    }
    // Nie ganz ohne Höhe bzw. Breite (siehe _nonFlat).
    final b = path.getBounds();
    if (b.height < 0.05 || b.width < 0.05) {
      final e = at(pts.last);
      path.lineTo(e.dx + (b.width < 0.05 ? 0.05 : 0), e.dy + (b.height < 0.05 ? 0.05 : 0));
    }
    canvas.drawPath(
      path,
      paint
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = math.max(0.5, widthFor(pts.first.pressure)),
    );
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

/// Malt die Teilstücke [from]..[to] eines entstehenden Leuchtstift-Strichs
/// (gleichmässig breit, in voller Farbe – durchsichtig wird er als Ganzes).
void paintHighlighterSegments(
  Canvas canvas,
  Size size,
  Color color,
  double width,
  List<InkPoint> pts,
  int from,
  int to,
) {
  final paint = Paint()
    ..color = color
    ..strokeCap = StrokeCap.round
    ..strokeWidth = width * size.width
    ..isAntiAlias = true;
  for (var i = math.max(1, from); i < to; i++) {
    final a = pts[i - 1], b = pts[i];
    final (p, q) = _nonFlat(Offset(a.x * size.width, a.y * size.height), Offset(b.x * size.width, b.y * size.height));
    canvas.drawLine(p, q, paint);
  }
}

void _drawSegments(Canvas canvas, Size size, Paint paint, double w, List<InkPoint> pts, int from, int to) {
  for (var i = from; i < to; i++) {
    final a = pts[i - 1], b = pts[i];
    paint.strokeWidth = math.max(0.5, w * (0.35 + 1.3 * (a.pressure + b.pressure) / 2));
    final (p, q) = _nonFlat(Offset(a.x * size.width, a.y * size.height), Offset(b.x * size.width, b.y * size.height));
    canvas.drawLine(p, q, paint);
  }
}

/// Ganz waagrechte oder senkrechte Linien (am Lineal) ganz leicht schräg
/// stellen (0,05 Punkte, unsichtbar). Manche Grafikkarten lassen Formen ohne
/// Höhe bzw. Breite beim Malen ins Seitenbild weg.
(Offset, Offset) _nonFlat(Offset a, Offset b) {
  final dx = (a.dx - b.dx).abs() < 0.05 ? 0.05 : 0.0;
  final dy = (a.dy - b.dy).abs() < 0.05 ? 0.05 : 0.0;
  return (a, b + Offset(dx, dy));
}
