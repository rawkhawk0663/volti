import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../app/theme.dart';
import '../../core/library/page_setup.dart';
import '../../core/pdf/auto_crop.dart';
import '../../core/pdf/page_image_cache.dart';
import 'cropped_page.dart';

/// Seiten eines Stücks anordnen und zuschneiden. Gibt die neue Einrichtung
/// zurück (null = abgebrochen). Das PDF selbst wird nie verändert.
Future<PageSetup?> showPageSetup(
  BuildContext context, {
  required PdfDocument doc,
  required PageSetup setup,
  required String title,
}) => Navigator.of(context).push<PageSetup>(
  MaterialPageRoute(
    builder: (_) => _PageSetupScreen(doc: doc, setup: setup, title: title),
    fullscreenDialog: true,
  ),
);

class _PageSetupScreen extends StatefulWidget {
  const _PageSetupScreen({required this.doc, required this.setup, required this.title});
  final PdfDocument doc;
  final PageSetup setup;
  final String title;

  @override
  State<_PageSetupScreen> createState() => _PageSetupScreenState();
}

class _PageSetupScreenState extends State<_PageSetupScreen> {
  late final int _n = widget.doc.pages.length;
  late final List<int> _order = widget.setup.pages(_n);
  late final Map<int, PageCrop> _crops = {...widget.setup.crops};
  late final PageImageCache _thumbs = PageImageCache(widget.doc, capacity: 64);
  bool _busy = false;

  static const _thumbHeight = 150.0;

  @override
  void dispose() {
    _thumbs.dispose();
    super.dispose();
  }

  PageCrop _crop(int src) => _crops[src] ?? PageCrop.none;

  List<int> get _hidden => [
    for (var p = 1; p <= _n; p++)
      if (!_order.contains(p)) p,
  ];

  void _setCrop(int src, PageCrop c) => setState(() => c.isNone ? _crops.remove(src) : _crops[src] = c.normalized());

  PageSetup _result() {
    final natural = _order.length == _n && [for (var i = 0; i < _n; i++) _order[i] == i + 1].every((b) => b);
    return widget.setup.withOrder(natural ? null : _order).withCrops(_crops);
  }

  Future<void> _autoAll() async {
    setState(() => _busy = true);
    for (final src in {..._order}) {
      final found = await autoCropPage(widget.doc, src);
      if (!mounted) return;
      if (found != null) {
        _setCrop(src, _crop(src).copyWith(left: found.left, top: found.top, right: found.right, bottom: found.bottom));
      }
    }
    setState(() => _busy = false);
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alles zurücksetzen?'),
        content: const Text(
          'Alle Seiten werden wieder so gezeigt wie im PDF: vollständig, in der ursprünglichen Reihenfolge, ohne Zuschnitt.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Zurücksetzen')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _order
        ..clear()
        ..addAll([for (var i = 1; i <= _n; i++) i]);
      _crops.clear();
    });
  }

  Future<void> _editCrop(int src) async {
    final r = await showCropEditor(context, doc: widget.doc, cache: _thumbs, page: src, crop: _crop(src));
    if (r == null) return;
    if (r.forAll) {
      setState(() {
        for (final p in {..._order}) {
          final c = r.crop;
          // Gleicher Ausschnitt und gleiche Drehung für alle Seiten.
          c.isNone ? _crops.remove(p) : _crops[p] = c.normalized();
        }
      });
    } else {
      _setCrop(src, r.crop);
    }
  }

  void _showAgain(int p) {
    setState(() {
      final i = _order.indexWhere((o) => o > p);
      i < 0 ? _order.add(p) : _order.insert(i, p);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hint = Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final hidden = _hidden;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Abbrechen',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Seiten · ${widget.title}'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _autoAll,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.crop_free),
            label: const Text('Ränder entfernen'),
          ),
          TextButton(onPressed: _reset, child: const Text('Zurücksetzen')),
          const SizedBox(width: 8),
          FilledButton(onPressed: () => Navigator.of(context).pop(_result()), child: const Text('Fertig')),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Das PDF bleibt unverändert – Volti merkt sich nur, wie die Seiten gezeigt werden. '
              'Am Griff ☰ ziehen ändert die Reihenfolge. Eine Seite doppelt zeigen geht z. B. für Wiederholungen '
              '(Anmerkungen erscheinen dann auf beiden). «Ränder entfernen» schneidet weisse Ränder bei allen Seiten weg.',
              style: hint,
            ),
          ),
          if (hidden.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Ausgeblendet:', style: hint),
                  for (final p in hidden)
                    ActionChip(
                      avatar: const Icon(Icons.visibility_outlined, size: 18),
                      label: Text('Seite $p'),
                      tooltip: 'Wieder anzeigen',
                      onPressed: () => _showAgain(p),
                    ),
                ],
              ),
            ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              buildDefaultDragHandles: false,
              itemCount: _order.length,
              onReorderItem: (from, to) => setState(() => _order.insert(to, _order.removeAt(from))),
              itemBuilder: (context, i) {
                final src = _order[i];
                final crop = _crop(src);
                final aspect = crop.displayAspect(_thumbs.aspectRatio(src));
                final duplicates = _order.where((o) => o == src).length;
                return Padding(
                  key: ValueKey('$i/$src'),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Material(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: i,
                            child: const MouseRegion(
                              cursor: SystemMouseCursors.grab,
                              child: Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle)),
                            ),
                          ),
                          InkWell(
                            onTap: () => _editCrop(src),
                            child: Container(
                              color: VoltiColors.anthracite,
                              padding: const EdgeInsets.all(4),
                              child: _Thumb(
                                cache: _thumbs,
                                page: src,
                                crop: crop,
                                height: _thumbHeight,
                                aspect: aspect,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${i + 1}', style: Theme.of(context).textTheme.titleLarge),
                                Text(
                                  src == i + 1 && duplicates == 1
                                      ? 'PDF-Seite $src'
                                      : 'PDF-Seite $src${duplicates > 1 ? ' (mehrfach)' : ''}',
                                  style: hint,
                                ),
                                if (!crop.isNone)
                                  Text(
                                    [
                                      if (crop.width < 1 || crop.height < 1) 'zugeschnitten',
                                      if (crop.quarterTurns != 0) 'gedreht ${crop.quarterTurns * 90}°',
                                      if (crop.skew != 0) 'gerade gerichtet ${crop.skew.toStringAsFixed(1)}°',
                                    ].join(' · '),
                                    style: hint,
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Zuschneiden …',
                            icon: const Icon(Icons.crop),
                            onPressed: () => _editCrop(src),
                          ),
                          IconButton(
                            tooltip: 'Drehen',
                            icon: const Icon(Icons.rotate_right),
                            onPressed: () => _setCrop(src, crop.copyWith(quarterTurns: crop.quarterTurns + 1)),
                          ),
                          IconButton(
                            tooltip: 'Doppelt zeigen',
                            icon: const Icon(Icons.library_add_outlined),
                            onPressed: () => setState(() => _order.insert(i + 1, src)),
                          ),
                          IconButton(
                            tooltip: duplicates > 1 ? 'Hier entfernen' : 'Ausblenden',
                            icon: const Icon(Icons.visibility_off_outlined),
                            onPressed: _order.length <= 1 ? null : () => setState(() => _order.removeAt(i)),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Vorschaubild einer Seite mit Zuschnitt.
class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.cache,
    required this.page,
    required this.crop,
    required this.height,
    required this.aspect,
  });
  final PageImageCache cache;
  final int page;
  final PageCrop crop;
  final double height;
  final double aspect;

  @override
  Widget build(BuildContext context) {
    final size = Size(height * aspect, height);
    final full = CroppedPage.fullSizeFor(crop, size);
    final px = ((full.width * MediaQuery.devicePixelRatioOf(context) / 128).ceil() * 128).clamp(128, 1536);
    return ColoredBox(
      color: Colors.white,
      child: CroppedPage(
        crop: crop,
        size: size,
        page: (_) => ListenableBuilder(
          listenable: cache,
          builder: (context, _) {
            final img = cache.imageFor(page, px);
            return img == null ? const SizedBox.expand() : RawImage(image: img, fit: BoxFit.fill);
          },
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ Zuschneiden

/// Ausschnitt einer Seite bearbeiten. [forAll]: für alle Seiten übernehmen.
Future<({PageCrop crop, bool forAll})?> showCropEditor(
  BuildContext context, {
  required PdfDocument doc,
  required PageImageCache cache,
  required int page,
  required PageCrop crop,
}) => showDialog(
  context: context,
  builder: (_) => _CropEditor(doc: doc, cache: cache, page: page, initial: crop),
);

enum _Grip { move, l, t, r, b, tl, tr, bl, br }

class _CropEditor extends StatefulWidget {
  const _CropEditor({required this.doc, required this.cache, required this.page, required this.initial});
  final PdfDocument doc;
  final PageImageCache cache;
  final int page;
  final PageCrop initial;

  @override
  State<_CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<_CropEditor> {
  late PageCrop _c = widget.initial;
  bool _forAll = false;
  bool _busy = false;
  _Grip? _grip;

  Future<void> _auto() async {
    setState(() => _busy = true);
    final found = await autoCropPage(widget.doc, widget.page);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (found != null) _c = _c.copyWith(left: found.left, top: found.top, right: found.right, bottom: found.bottom);
    });
  }

  _Grip? _gripAt(Offset p, Size s) {
    const reach = 26.0;
    final r = Rect.fromLTRB(_c.left * s.width, _c.top * s.height, _c.right * s.width, _c.bottom * s.height);
    final nl = (p.dx - r.left).abs() < reach, nr = (p.dx - r.right).abs() < reach;
    final nt = (p.dy - r.top).abs() < reach, nb = (p.dy - r.bottom).abs() < reach;
    final inX = p.dx > r.left - reach && p.dx < r.right + reach, inY = p.dy > r.top - reach && p.dy < r.bottom + reach;
    if (nl && nt) return _Grip.tl;
    if (nr && nt) return _Grip.tr;
    if (nl && nb) return _Grip.bl;
    if (nr && nb) return _Grip.br;
    if (nl && inY) return _Grip.l;
    if (nr && inY) return _Grip.r;
    if (nt && inX) return _Grip.t;
    if (nb && inX) return _Grip.b;
    if (r.contains(p)) return _Grip.move;
    return null;
  }

  void _drag(Offset delta, Size s) {
    final dx = delta.dx / s.width, dy = delta.dy / s.height;
    var l = _c.left, t = _c.top, r = _c.right, b = _c.bottom;
    switch (_grip) {
      case _Grip.move:
        final mx = dx.clamp(-l, 1 - r), my = dy.clamp(-t, 1 - b);
        l += mx;
        r += mx;
        t += my;
        b += my;
      case _Grip.l:
        l += dx;
      case _Grip.r:
        r += dx;
      case _Grip.t:
        t += dy;
      case _Grip.b:
        b += dy;
      case _Grip.tl:
        l += dx;
        t += dy;
      case _Grip.tr:
        r += dx;
        t += dy;
      case _Grip.bl:
        l += dx;
        b += dy;
      case _Grip.br:
        r += dx;
        b += dy;
      case null:
        return;
    }
    setState(
      () => _c = PageCrop(
        left: l,
        top: t,
        right: r,
        bottom: b,
        quarterTurns: _c.quarterTurns,
        skew: _c.skew,
      ).normalized(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context);
    final aspect = widget.cache.aspectRatio(widget.page);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 980, maxHeight: screen.height - 32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Seite ${widget.page} zuschneiden', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Ecken und Kanten ziehen, um den Ausschnitt zu wählen. In der Mitte ziehen verschiebt ihn.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ColoredBox(
                  color: VoltiColors.anthracite,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Center(
                      child: RotatedBox(
                        quarterTurns: _c.quarterTurns,
                        child: AspectRatio(
                          aspectRatio: aspect,
                          child: LayoutBuilder(
                            builder: (context, box) {
                              final s = box.biggest;
                              final px = ((s.width * MediaQuery.devicePixelRatioOf(context) / 128).ceil() * 128).clamp(
                                128,
                                2048,
                              );
                              return MouseRegion(
                                cursor: SystemMouseCursors.precise,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanStart: (d) => _grip = _gripAt(d.localPosition, s),
                                  onPanUpdate: (d) => _drag(d.delta, s),
                                  onPanEnd: (_) => _grip = null,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ColoredBox(
                                        color: Colors.white,
                                        child: Transform.rotate(
                                          angle: _c.skew * 3.141592653589793 / 180,
                                          child: ListenableBuilder(
                                            listenable: widget.cache,
                                            builder: (context, _) {
                                              final img = widget.cache.imageFor(widget.page, px);
                                              return img == null
                                                  ? const Center(child: CircularProgressIndicator())
                                                  : RawImage(image: img, fit: BoxFit.fill);
                                            },
                                          ),
                                        ),
                                      ),
                                      CustomPaint(painter: _CropPainter(_c, scheme.primary)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _auto,
                    icon: _busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.crop_free),
                    label: const Text('Ränder automatisch'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _c = PageCrop(quarterTurns: _c.quarterTurns, skew: _c.skew)),
                    icon: const Icon(Icons.fullscreen),
                    label: const Text('Ganze Seite'),
                  ),
                  IconButton(
                    tooltip: 'Nach links drehen',
                    icon: const Icon(Icons.rotate_left),
                    onPressed: () => setState(() => _c = _c.copyWith(quarterTurns: _c.quarterTurns + 3)),
                  ),
                  IconButton(
                    tooltip: 'Nach rechts drehen',
                    icon: const Icon(Icons.rotate_right),
                    onPressed: () => setState(() => _c = _c.copyWith(quarterTurns: _c.quarterTurns + 1)),
                  ),
                  SizedBox(
                    width: 300,
                    child: Row(
                      children: [
                        const Text('Gerade richten'),
                        Expanded(
                          child: Slider(
                            min: -PageCrop.maxSkew,
                            max: PageCrop.maxSkew,
                            divisions: 100,
                            value: _c.skew,
                            label: '${_c.skew.toStringAsFixed(1)}°',
                            onChanged: (v) => setState(() => _c = _c.copyWith(skew: v)),
                          ),
                        ),
                        SizedBox(width: 44, child: Text('${_c.skew.toStringAsFixed(1)}°')),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Checkbox(value: _forAll, onChanged: (v) => setState(() => _forAll = v ?? false)),
                  const Flexible(child: Text('Für alle Seiten übernehmen')),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop((crop: _c, forAll: _forAll)),
                    child: const Text('Übernehmen'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dunkelt alles ausserhalb des Ausschnitts ab und zeigt Rahmen und Griffe.
class _CropPainter extends CustomPainter {
  _CropPainter(this.c, this.color);
  final PageCrop c;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTRB(c.left * s.width, c.top * s.height, c.right * s.width, c.bottom * s.height);
    final shade = Paint()..color = const Color(0x99000000);
    final outer = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & s)
      ..addRect(r);
    canvas.drawPath(outer, shade);
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
    final grip = Paint()..color = color;
    for (final p in [
      r.topLeft,
      r.topRight,
      r.bottomLeft,
      r.bottomRight,
      r.centerLeft,
      r.centerRight,
      r.topCenter,
      r.bottomCenter,
    ]) {
      canvas.drawCircle(p, 7, Paint()..color = Colors.white);
      canvas.drawCircle(p, 5, grip);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.c != c || old.color != color;
}
