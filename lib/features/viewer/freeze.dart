import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Zeigt [child] während des Zeichnens als fertiges Bild.
///
/// Flutter malt alle Vektor-Zeichnungen (Symbole, Schrift, Regler) bei jedem
/// Bild neu. Gemessen: Das offene Werkzeug-Fenster verdoppelt so die Zeit pro
/// Bild beim Schreiben. Solange der Stift schreibt, ändert sich darin nichts –
/// also wird beim Aufsetzen einmal ein Bild davon gemacht und nur noch dieses
/// gezeigt. Beim Absetzen erscheint wieder das echte Fenster.
class FreezeWhileDrawing extends StatefulWidget {
  const FreezeWhileDrawing({super.key, required this.drawing, required this.child});
  final ValueListenable<bool> drawing;
  final Widget child;

  @override
  State<FreezeWhileDrawing> createState() => _FreezeWhileDrawingState();
}

class _FreezeWhileDrawingState extends State<FreezeWhileDrawing> {
  final _key = GlobalKey();
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    widget.drawing.addListener(_onDrawing);
  }

  @override
  void didUpdateWidget(FreezeWhileDrawing old) {
    super.didUpdateWidget(old);
    if (old.drawing != widget.drawing) {
      old.drawing.removeListener(_onDrawing);
      widget.drawing.addListener(_onDrawing);
    }
  }

  void _onDrawing() {
    if (!mounted) return;
    if (widget.drawing.value) {
      final ro = _key.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary || !ro.attached || ro.debugNeedsPaint || ro.size.isEmpty) return;
      try {
        final img = ro.toImageSync(pixelRatio: MediaQuery.devicePixelRatioOf(context));
        setState(() => _replace(img));
      } catch (_) {
        // Dann eben ohne Bild.
      }
    } else if (_image != null) {
      setState(() => _replace(null));
    }
  }

  void _replace(ui.Image? img) {
    final old = _image;
    _image = img;
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    widget.drawing.removeListener(_onDrawing);
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    return Stack(
      children: [
        // Unsichtbar (Deckkraft 0 malt nichts), behält aber Grösse und Zustand.
        Opacity(
          opacity: img == null ? 1 : 0,
          child: RepaintBoundary(key: _key, child: widget.child),
        ),
        if (img != null)
          Positioned.fill(
            child: IgnorePointer(
              child: RawImage(image: img, fit: BoxFit.fill),
            ),
          ),
      ],
    );
  }
}
