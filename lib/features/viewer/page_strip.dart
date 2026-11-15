import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'page_export.dart';

/// Kleine Seitenbilder für die Bildleiste unten in der Notenansicht.
///
/// Gerendert wird im Hintergrund, eines nach dem anderen, zuletzt gewünschte
/// zuerst (also die gerade sichtbaren). [forget] verwirft die Bilder eines
/// Stücks, z. B. nach dem Bearbeiten, damit neue Anmerkungen erscheinen.
class StripThumbs {
  StripThumbs({this.width = 220});
  final int width;

  final Map<(Object, int), ValueNotifier<ui.Image?>> _images = {};
  final Map<(Object, int), ExportPiece Function()> _sources = {};
  final List<(Object, int)> _wanted = [];
  bool _rendering = false, _disposed = false;

  /// Bild der PDF-Seite [pdfPage] des Stücks [owner].
  ValueNotifier<ui.Image?> get(Object owner, int pdfPage, ExportPiece Function() piece) {
    final key = (owner, pdfPage);
    final existing = _images[key];
    if (existing != null) return existing;
    final n = _images[key] = ValueNotifier<ui.Image?>(null);
    _sources[key] = piece;
    _wanted.add(key);
    _pump();
    return n;
  }

  /// Schon vorhandenes Bild (ohne neu zu rendern), sonst null.
  ValueNotifier<ui.Image?>? peek(Object owner, int pdfPage) => _images[(owner, pdfPage)];

  /// Bilder eines Stücks verwerfen (null = alle). Die Anzeige holt sie neu.
  void forget([Object? owner]) {
    final keys = _images.keys.where((k) => owner == null || k.$1 == owner).toList();
    for (final k in keys) {
      final n = _images.remove(k)!;
      _sources.remove(k);
      _wanted.remove(k);
      // Erst nach dem nächsten Bild freigeben: die Anzeige könnte es noch zeigen.
      final img = n.value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        img?.dispose();
        n.dispose();
      });
    }
  }

  Future<void> _pump() async {
    if (_rendering) return;
    _rendering = true;
    try {
      while (_wanted.isNotEmpty && !_disposed) {
        final key = _wanted.removeLast();
        final source = _sources[key];
        if (source == null) continue;
        final e = source();
        final page = key.$2;
        ui.Image? img;
        try {
          img = await renderPageAsShown(
            e.doc,
            e.annotations,
            e.setup.cropOf(page),
            page,
            width: width,
            paper: e.setup.paperOf(page),
          );
        } catch (_) {
          img = null; // z. B. Stück inzwischen geschlossen
        }
        final target = _images[key];
        if (_disposed || target == null) {
          img?.dispose();
          continue;
        }
        target.value = img;
      }
    } finally {
      _rendering = false;
    }
  }

  void dispose() {
    _disposed = true;
    for (final n in _images.values) {
      n.value?.dispose();
      n.dispose();
    }
    _images.clear();
  }
}

/// Bildleiste unten in der Mitte, im Stil eines Docks: alle Seiten des
/// Stücks als kleine Bilder auf einer abgerundeten, schwebenden Fläche.
/// Wischen blättert durch die Leiste, Antippen springt zur Seite. Mit der
/// Maus wird die Seite unter dem Zeiger (und etwas ihre Nachbarn) grösser.
class PageStrip extends StatefulWidget {
  const PageStrip({
    super.key,
    required this.count,
    required this.current,
    required this.thumb,
    required this.onTap,
    this.onTouch,
    this.visible = true,
  });

  /// Anzahl angezeigter Seiten.
  final int count;

  /// Gerade sichtbare Seiten (ab 1).
  final Set<int> current;

  /// Bild der angezeigten Seite (ab 1); null = (noch) keines.
  final ValueNotifier<ui.Image?>? Function(int display) thumb;
  final void Function(int display) onTap;

  /// Bei jeder Berührung (hält die Leiste offen).
  final VoidCallback? onTouch;

  /// Ist die Leiste gerade eingeblendet? (Beim Einblenden steht die aktuelle
  /// Seite wieder in der Mitte, auch wenn vorher durch die Leiste gewischt wurde.)
  final bool visible;

  /// Höhe der Fläche samt Abstand zum Rand (ohne den Platz fürs Vergrössern).
  static const height = _dock + _margin;

  static const _dock = 92.0, _margin = 10.0, _headroom = 26.0;
  static const _itemExtent = 64.0, _pad = 10.0;

  /// So viele Plätze hat das Dock höchstens (dann wird gewischt).
  static const _maxSlots = 15;

  @override
  State<PageStrip> createState() => _PageStripState();
}

class _PageStripState extends State<PageStrip> {
  static final _none = ValueNotifier<ui.Image?>(null);

  ScrollController? _scroll;

  /// Seite unter dem Mauszeiger (ab 1), null = keine.
  int? _hover;

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  /// Versatz, bei dem die aktuelle Seite genau in der Mitte des Docks steht
  /// (Wunsch des Besitzers: immer, auch bei der ersten und letzten Seite).
  /// Links und rechts ist dafür je ein halbes Dock Platz.
  double _offsetFor(Set<int> current) {
    if (current.isEmpty) return 0;
    final first = current.reduce(math.min), last = current.reduce(math.max);
    final center = (first + last) / 2 - 1;
    return (center * PageStrip._itemExtent).clamp(0.0, math.max(0, widget.count - 1) * PageStrip._itemExtent);
  }

  void _recenter({bool animate = true}) {
    final s = _scroll;
    if (s == null || !s.hasClients) return;
    final target = _offsetFor(widget.current);
    if (animate) {
      s.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      s.jumpTo(target);
    }
  }

  @override
  void didUpdateWidget(PageStrip old) {
    super.didUpdateWidget(old);
    if (old.current.length != widget.current.length || !old.current.containsAll(widget.current)) {
      _recenter();
    } else if (widget.visible && !old.visible) {
      _recenter(animate: false);
    }
  }

  /// Vergrösserung wie im Dock: die Seite unter der Maus am meisten,
  /// die Nachbarn etwas, die aktuelle Seite leicht.
  double _scaleOf(int page, bool here) {
    final h = _hover;
    var scale = here ? 1.14 : 1.0;
    if (h != null) {
      final d = (page - h).abs();
      if (d < 2) scale = math.max(scale, 1 + 0.32 * (1 - d / 2));
    }
    return scale;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Listener(
      onPointerDown: (_) => widget.onTouch?.call(),
      // Mausrad: waagrecht durch die Leiste.
      onPointerSignal: (e) {
        final s = _scroll;
        if (e is PointerScrollEvent && s != null && s.hasClients) {
          final d = e.scrollDelta.dx != 0 ? e.scrollDelta.dx : e.scrollDelta.dy;
          s.jumpTo((s.offset + d).clamp(0.0, s.position.maxScrollExtent));
        }
      },
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: PageStrip._margin),
          child: LayoutBuilder(
            builder: (context, box) {
              // Breit genug, dass links und rechts der Mitte alle übrigen Seiten
              // Platz hätten (höchstens [_maxSlots] Plätze, ungerade Zahl).
              final slots = math.min(2 * widget.count - 1, PageStrip._maxSlots);
              final fit = ((box.maxWidth - 32 - 2 * PageStrip._pad) / PageStrip._itemExtent).floor();
              final n = math.max(1, math.min(slots, fit.isOdd ? fit : fit - 1));
              final width = n * PageStrip._itemExtent + 2 * PageStrip._pad;
              // Seitenrand so, dass die erste und die letzte Seite in die Mitte rücken können.
              final side = (width - PageStrip._itemExtent) / 2;
              _scroll ??= ScrollController(initialScrollOffset: _offsetFor(widget.current));
              return Center(
                heightFactor: 1,
                child: SizedBox(
                  width: width,
                  height: PageStrip._dock + PageStrip._headroom,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Die Fläche des Docks (deckend, ohne Schatten – das bleibt schnell).
                      Positioned.fill(
                        top: PageStrip._headroom,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: dark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
                          ),
                        ),
                      ),
                      // Seiten: seitlich abgeschnitten, nach oben dürfen sie beim
                      // Vergrössern über die Fläche hinausragen.
                      // Nur die Fläche selbst nimmt Berührungen an (darüber bleibt
                      // die Notenseite bedienbar).
                      Positioned.fill(
                        top: PageStrip._headroom,
                        child: ClipRect(
                          clipper: const _SideClipper(inset: 1),
                          child: MouseRegion(
                            onExit: (_) => setState(() => _hover = null),
                            child: ListView.builder(
                              controller: _scroll,
                              clipBehavior: Clip.none,
                              scrollDirection: Axis.horizontal,
                              padding: EdgeInsets.symmetric(horizontal: side),
                              itemExtent: PageStrip._itemExtent,
                              itemCount: widget.count,
                              itemBuilder: (context, i) => _item(context, i + 1),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, int page) {
    final scheme = Theme.of(context).colorScheme;
    final here = widget.current.contains(page);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = page),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTap(page),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
          child: Column(
            children: [
              Expanded(
                child: AnimatedScale(
                  scale: _scaleOf(page, here),
                  alignment: Alignment.bottomCenter,
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: here ? scheme.primary : scheme.outlineVariant, width: here ? 2.5 : 1),
                    ),
                    padding: const EdgeInsets.all(1),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: ValueListenableBuilder<ui.Image?>(
                        valueListenable: widget.thumb(page) ?? _none,
                        builder: (context, img, _) => img == null
                            ? ColoredBox(color: scheme.surfaceContainerHighest)
                            : RawImage(image: img, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 16,
                child: Center(
                  child: Text(
                    '$page',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: here ? FontWeight.w700 : FontWeight.w400,
                      color: here ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Schneidet nur links und rechts ab (oben darf etwas hinausragen).
class _SideClipper extends CustomClipper<Rect> {
  const _SideClipper({this.inset = 0});
  final double inset;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(inset, -1000, size.width - inset, size.height);

  @override
  bool shouldReclip(_SideClipper old) => old.inset != inset;
}
