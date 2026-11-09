import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/library/page_setup.dart';
import '../../core/pdf/systems.dart';
import 'page_export.dart';

/// Endlosband: die Notenzeilen eines Stücks untereinander, so breit wie der
/// Bildschirm – grösser als auf der Seite und zum Durchscrollen. Mit den
/// Anmerkungen. Pedal, Pfeiltasten und Leertaste scrollen ein Stück weiter.
Future<void> showReflow(BuildContext context, {required String title, required ExportPiece piece}) =>
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ReflowScreen(title: title, piece: piece),
        fullscreenDialog: true,
      ),
    );

/// Ein Streifen: Ausschnitt eines Seitenbilds.
class _Strip {
  const _Strip(this.image, this.src);
  final ui.Image image;
  final Rect src;
}

class _ReflowScreen extends StatefulWidget {
  const _ReflowScreen({required this.title, required this.piece});
  final String title;
  final ExportPiece piece;

  @override
  State<_ReflowScreen> createState() => _ReflowScreenState();
}

class _ReflowScreenState extends State<_ReflowScreen> {
  final List<_Strip> _strips = [];
  final List<ui.Image> _images = [];
  final _scroll = ScrollController();
  int _done = 0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final p = widget.piece;
    for (final page in p.pages) {
      final img = await renderPageAsShown(p.doc, p.annotations, p.setup.cropOf(page), page, width: 1400);
      if (_disposed) {
        img?.dispose();
        return;
      }
      if (img != null) {
        _images.add(img);
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        final px = data!.buffer.asUint8List();
        final sides = findContentBounds(px, img.width, img.height, margin: 0.015) ?? PageCrop.none;
        var bands = findSystems(px, img.width, img.height);
        if (bands.isEmpty) bands = const [(top: 0.0, bottom: 1.0)];
        final w = img.width.toDouble(), h = img.height.toDouble();
        for (final b in bands) {
          _strips.add(_Strip(img, Rect.fromLTRB(sides.left * w, b.top * h, sides.right * w, b.bottom * h)));
        }
      }
      if (mounted) setState(() => _done++);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _scroll.dispose();
    for (final i in _images) {
      i.dispose();
    }
    super.dispose();
  }

  void _step(double direction) {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final target = (pos.pixels + direction * pos.viewportDimension * 0.8).clamp(0.0, pos.maxScrollExtent);
    _scroll.animateTo(target, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.pageDown ||
        k == LogicalKeyboardKey.space) {
      _step(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.pageUp) {
      _step(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.piece.pages.length;
    final width = MediaQuery.sizeOf(context).width;
    final stripWidth = (width - 24).clamp(200.0, 1600.0);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: VoltiColors.anthracite,
        appBar: AppBar(
          backgroundColor: VoltiColors.anthracite,
          foregroundColor: Colors.white,
          title: Text('${widget.title} · Endlosband'),
          actions: [
            if (_done < total)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: Text('Seite $_done von $total …')),
              ),
          ],
        ),
        body: GestureDetector(
          // Unten antippen = weiter, oben = zurück (wie Umblättern)
          onTapUp: (d) => _step(d.localPosition.dy > MediaQuery.sizeOf(context).height / 2 ? 1 : -1),
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: _strips.length + (_done < total ? 1 : 0),
            itemBuilder: (context, i) {
              if (i >= _strips.length) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final s = _strips[i];
              return Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: SizedBox(
                    width: stripWidth,
                    height: stripWidth * s.src.height / s.src.width,
                    child: CustomPaint(painter: _StripPainter(s)),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StripPainter extends CustomPainter {
  _StripPainter(this.strip);
  final _Strip strip;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    canvas.drawImageRect(strip.image, strip.src, Offset.zero & size, Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_StripPainter old) => !identical(old.strip, strip);
}
