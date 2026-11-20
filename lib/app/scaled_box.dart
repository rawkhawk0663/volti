import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Zeigt [child] um [scale] verkleinert (oder vergrössert) – und braucht auch
/// nur so viel Platz. Anders als `Transform.scale` stimmt damit die Grösse für
/// den Aufbau drumherum, und Berührungen treffen weiterhin genau.
///
/// Gebraucht für kleine Bildschirme (Handy), wo Werkzeugleiste und
/// Einstellungsfenster sonst zu viel von der Notenseite verdecken.
class ScaledBox extends SingleChildRenderObjectWidget {
  const ScaledBox({super.key, required this.scale, super.child});

  final double scale;

  @override
  RenderScaledBox createRenderObject(BuildContext context) => RenderScaledBox(scale);

  @override
  void updateRenderObject(BuildContext context, RenderScaledBox renderObject) => renderObject.scale = scale;
}

class RenderScaledBox extends RenderProxyBox {
  RenderScaledBox(this._scale);

  double _scale;
  double get scale => _scale;
  set scale(double v) {
    if (v == _scale) return;
    _scale = v;
    markNeedsLayout();
  }

  BoxConstraints _inner(BoxConstraints c) => BoxConstraints(
    minWidth: c.minWidth / _scale,
    maxWidth: c.maxWidth / _scale,
    minHeight: c.minHeight / _scale,
    maxHeight: c.maxHeight / _scale,
  );

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_inner(constraints), parentUsesSize: true);
    size = constraints.constrain(child.size * _scale);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return constraints.constrain(child.getDryLayout(_inner(constraints)) * _scale);
  }

  @override
  double computeMinIntrinsicWidth(double height) => (child?.getMinIntrinsicWidth(height / _scale) ?? 0) * _scale;
  @override
  double computeMaxIntrinsicWidth(double height) => (child?.getMaxIntrinsicWidth(height / _scale) ?? 0) * _scale;
  @override
  double computeMinIntrinsicHeight(double width) => (child?.getMinIntrinsicHeight(width / _scale) ?? 0) * _scale;
  @override
  double computeMaxIntrinsicHeight(double width) => (child?.getMaxIntrinsicHeight(width / _scale) ?? 0) * _scale;

  Matrix4 get _transform => Matrix4.diagonal3Values(_scale, _scale, 1);

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (_scale == 1) {
      context.paintChild(child, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      (c, o) => c.paintChild(child, o),
      oldLayer: layer is TransformLayer ? layer as TransformLayer : null,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (r, p) => child.hitTest(r, position: p),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) => transform.multiply(_transform);
}

/// Verkleinerung für schwebende Leisten und Fenster auf kleinen Bildschirmen
/// (Handy: kürzere Seite unter 600 Punkten). Auf Tablet und Computer 1.
double compactScale(Size screen) => screen.shortestSide < 600 ? 0.78 : 1.0;
