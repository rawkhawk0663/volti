import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'tool_controller.dart';

/// Vergrösserung der Notenansicht (Zoom).
///
/// * Während der Geste wird das Bild nur verschoben und vergrössert (schnell,
///   eine Weile leicht unscharf).
/// * Kurz danach wird in der neuen Grösse scharf gerendert ([renderScale]).
class PageZoom {
  static const maxScale = 4.0;

  /// Vergrösserung und Verschiebung (für das `Transform`).
  final ValueNotifier<Matrix4> matrix = ValueNotifier(Matrix4.identity());

  /// Für scharfes Rendern: die Vergrösserung, für die die Seiten-Bilder
  /// gerade gemacht sind (in halben Schritten, erst nach der Geste).
  final ValueNotifier<double> renderScale = ValueNotifier(1);

  double _scale = 1;
  Offset _offset = Offset.zero;
  Size _area = Size.zero;
  Timer? _sharpen;
  DateTime _moved = DateTime(2000);

  double get scale => _scale;
  bool get isZoomed => _scale > 1.01;

  /// Wurde gerade gezoomt oder verschoben? Dann ist ein Antippen bzw. Wischen
  /// kein Umblättern.
  bool get recentlyMoved => DateTime.now().difference(_moved) < const Duration(milliseconds: 350);

  void _markMoved() => _moved = DateTime.now();

  /// [focal] bleibt dabei an derselben Stelle (Koordinaten der Fläche).
  void set(double scale, Offset offset) {
    final s = scale.clamp(1.0, maxScale);
    // Nie über den Rand hinaus verschieben: Die Fläche bleibt ganz bedeckt.
    final minX = _area.width - _area.width * s, minY = _area.height - _area.height * s;
    final o = Offset(offset.dx.clamp(minX, 0.0), offset.dy.clamp(minY, 0.0));
    if (s == _scale && o == _offset) return;
    _scale = s;
    _offset = o;
    matrix.value = Matrix4.identity()
      ..translateByDouble(o.dx, o.dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
    _scheduleSharpen();
  }

  /// Um [factor] vergrössern, [focal] bleibt an seinem Platz.
  void zoomBy(double factor, Offset focal) {
    final s = (_scale * factor).clamp(1.0, maxScale);
    final content = (focal - _offset) / _scale;
    set(s, focal - content * s);
    _markMoved();
  }

  void panBy(Offset delta) {
    if (!isZoomed) return;
    set(_scale, _offset + delta);
    _markMoved();
  }

  void reset() {
    _sharpen?.cancel();
    if (_scale != 1 || _offset != Offset.zero) {
      _scale = 1;
      _offset = Offset.zero;
      matrix.value = Matrix4.identity();
    }
    renderScale.value = 1;
  }

  void _scheduleSharpen() {
    _sharpen?.cancel();
    _sharpen = Timer(const Duration(milliseconds: 280), () {
      // In halben Schritten, damit nicht jede kleine Änderung neu rendert.
      final target = isZoomed ? ((_scale * 2).ceil() / 2).clamp(1.0, maxScale) : 1.0;
      renderScale.value = target;
    });
  }

  void dispose() {
    _sharpen?.cancel();
    matrix.dispose();
    renderScale.dispose();
  }
}

/// Fläche, in der man mit zwei Fingern zoomt und mit einem Finger (wenn
/// vergrössert) verschiebt. Am Computer: Strg + Mausrad, Touchpad-Geste,
/// Mausrad verschiebt.
///
/// Der Stift zoomt nie. Solange der Stift in der Nähe ist (darüber schwebt
/// oder schreibt), werden Finger ignoriert – sonst würde der Handballen beim
/// Schreiben die Seite verschieben.
class ZoomArea extends StatefulWidget {
  const ZoomArea({super.key, required this.zoom, required this.tools, required this.child});
  final PageZoom zoom;
  final ToolController tools;
  final Widget child;

  @override
  State<ZoomArea> createState() => _ZoomAreaState();
}

class _ZoomAreaState extends State<ZoomArea> {
  PageZoom get zoom => widget.zoom;

  final Map<int, Offset> _touches = {};
  DateTime _penSeen = DateTime(2000);
  int _pensDown = 0;

  // Zwei-Finger-Geste
  double? _startDist;
  double _startScale = 1;
  Offset _startFocal = Offset.zero;
  Offset _startOffset = Offset.zero;

  // Ein Finger: verschieben erst ab einer kleinen Strecke (Antippen bleibt Antippen)
  Offset _panTravel = Offset.zero;
  bool _panning = false;

  // Touchpad
  double _padStartScale = 1;

  bool get _penNear => _pensDown > 0 || DateTime.now().difference(_penSeen) < const Duration(milliseconds: 700);

  static bool _isPen(PointerEvent e) =>
      e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;

  void _down(PointerDownEvent e) {
    if (_isPen(e)) {
      _pensDown++;
      _penSeen = DateTime.now();
      _cancelFingers();
      return;
    }
    if (e.kind != PointerDeviceKind.touch) return;
    if (widget.tools.rulerPointers.contains(e.pointer) || _penNear) return;
    _touches[e.pointer] = e.localPosition;
    if (_touches.length == 2) {
      _beginPinch();
    } else if (_touches.length == 1) {
      _panTravel = Offset.zero;
      _panning = false;
    }
  }

  void _beginPinch() {
    final pts = _touches.values.take(2).toList();
    _startDist = (pts[0] - pts[1]).distance;
    _startFocal = (pts[0] + pts[1]) / 2;
    _startScale = zoom.scale;
    _startOffset = zoom._offset;
  }

  void _move(PointerMoveEvent e) {
    if (_isPen(e)) {
      _penSeen = DateTime.now();
      return;
    }
    final prev = _touches[e.pointer];
    if (prev == null) return;
    if (widget.tools.rulerPointers.contains(e.pointer)) {
      _touches.remove(e.pointer);
      return;
    }
    _touches[e.pointer] = e.localPosition;
    if (_touches.length >= 2 && _startDist != null) {
      final pts = _touches.values.take(2).toList();
      final d = (pts[0] - pts[1]).distance;
      if (_startDist! < 1) return;
      final focal = (pts[0] + pts[1]) / 2;
      final s = (_startScale * d / _startDist!).clamp(1.0, PageZoom.maxScale);
      final content = (_startFocal - _startOffset) / _startScale;
      zoom.set(s, focal - content * s);
      zoom._markMoved();
    } else if (_touches.length == 1 && zoom.isZoomed) {
      final delta = e.localPosition - prev;
      _panTravel += delta;
      if (!_panning && _panTravel.distance > kTouchSlop) _panning = true;
      if (_panning) zoom.panBy(delta);
    }
  }

  void _up(PointerEvent e) {
    if (_isPen(e)) {
      _pensDown = math.max(0, _pensDown - 1);
      _penSeen = DateTime.now();
      return;
    }
    if (_touches.remove(e.pointer) == null) return;
    if (_touches.length == 2) {
      _beginPinch();
    } else if (_touches.length == 1) {
      // Nach dem Zoomen mit dem verbliebenen Finger weiter verschieben.
      _startDist = null;
      _panning = true;
    } else {
      _startDist = null;
      _panning = false;
    }
  }

  void _cancelFingers() {
    _touches.clear();
    _startDist = null;
    _panning = false;
  }

  void _hover(PointerHoverEvent e) {
    if (_isPen(e)) _penSeen = DateTime.now();
  }

  void _signal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed) {
      GestureBinding.instance.pointerSignalResolver.register(e, (_) {
        zoom.zoomBy(math.pow(1.0018, -e.scrollDelta.dy).toDouble(), e.localPosition);
      });
    } else if (zoom.isZoomed) {
      GestureBinding.instance.pointerSignalResolver.register(e, (_) {
        final d = keys.isShiftPressed ? Offset(-e.scrollDelta.dy, 0) : -e.scrollDelta;
        zoom.panBy(d);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        zoom._area = box.biggest;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          onPointerHover: _hover,
          onPointerSignal: _signal,
          onPointerPanZoomStart: (e) => _padStartScale = zoom.scale,
          onPointerPanZoomUpdate: (e) {
            final target = _padStartScale * e.scale;
            if ((target - zoom.scale).abs() > 0.001) zoom.zoomBy(target / zoom.scale, e.localPosition);
            if (zoom.isZoomed) zoom.panBy(e.panDelta);
          },
          child: ValueListenableBuilder<Matrix4>(
            valueListenable: zoom.matrix,
            builder: (context, m, child) => ClipRect(
              clipBehavior: m.isIdentity() ? Clip.none : Clip.hardEdge,
              child: Transform(transform: m, child: child),
            ),
            child: widget.child,
          ),
        );
      },
    );
  }
}
