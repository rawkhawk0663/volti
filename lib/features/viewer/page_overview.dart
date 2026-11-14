import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/l10n.dart';
import '../../app/window_buttons.dart';
import 'page_export.dart';

/// Ein Stück für die Seitenübersicht. [owned]: wurde nur für die Übersicht
/// geöffnet und muss danach wieder geschlossen werden.
typedef OverviewPiece = ({ExportPiece piece, bool owned});

/// Seitenübersicht: alle Seiten als kleine Bilder (mit Anmerkungen, so wie
/// sie angezeigt werden). Antippen springt hin. In einer Setlist lässt sich
/// oben der Song wählen.
///
/// Gibt (Stück, angezeigte Seite ab 1) zurück, oder null.
Future<({int piece, int page})?> showPageOverview(
  BuildContext context, {
  required List<String> titles,
  required int currentPiece,
  required Set<int> currentPages,
  required Future<OverviewPiece?> Function(int index) load,
}) => Navigator.of(context).push(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _PageOverview(titles: titles, currentPiece: currentPiece, currentPages: currentPages, load: load),
  ),
);

class _PageOverview extends StatefulWidget {
  const _PageOverview({
    required this.titles,
    required this.currentPiece,
    required this.currentPages,
    required this.load,
  });
  final List<String> titles;
  final int currentPiece;
  final Set<int> currentPages;
  final Future<OverviewPiece?> Function(int index) load;

  @override
  State<_PageOverview> createState() => _PageOverviewState();
}

class _PageOverviewState extends State<_PageOverview> {
  late int _piece = widget.currentPiece;
  final Map<int, Future<OverviewPiece?>> _loaded = {};
  final Map<(int, int), ValueNotifier<ui.Image?>> _thumbs = {};
  final List<(int, int)> _wanted = [];
  bool _rendering = false;
  bool _disposed = false;
  ScrollController? _scroll;
  int? _scrollPiece;

  static const _tileWidth = 190.0;
  static const _renderWidth = 380;

  Future<OverviewPiece?> _pieceAt(int i) => _loaded[i] ??= widget.load(i);

  @override
  void dispose() {
    _disposed = true;
    _scroll?.dispose();
    for (final n in _thumbs.values) {
      n.value?.dispose();
      n.dispose();
    }
    for (final f in _loaded.values) {
      f.then((p) async {
        if (p != null && p.owned) await closeExportPieces([p.piece]);
      });
    }
    super.dispose();
  }

  /// Vorschaubild einer Seite; wird bei Bedarf im Hintergrund gerendert
  /// (eines nach dem anderen, zuletzt gewünschte zuerst – also die sichtbaren).
  ValueNotifier<ui.Image?> _thumb(int piece, int index) {
    final key = (piece, index);
    final existing = _thumbs[key];
    if (existing != null) return existing;
    final n = _thumbs[key] = ValueNotifier<ui.Image?>(null);
    _wanted.add(key);
    _pump();
    return n;
  }

  Future<void> _pump() async {
    if (_rendering) return;
    _rendering = true;
    try {
      while (_wanted.isNotEmpty && !_disposed) {
        final key = _wanted.removeLast();
        final p = await _pieceAt(key.$1);
        if (p == null || _disposed) continue;
        final e = p.piece;
        if (key.$2 >= e.pages.length) continue;
        final page = e.pages[key.$2];
        final img = await renderPageAsShown(
          e.doc,
          e.annotations,
          e.setup.cropOf(page),
          page,
          width: _renderWidth,
          paper: e.setup.paperOf(page),
        );
        if (_disposed) {
          img?.dispose();
          return;
        }
        _thumbs[key]?.value = img;
      }
    } finally {
      _rendering = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final setlist = widget.titles.length > 1;
    return CallbackShortcuts(
      // Esc schliesst die Übersicht (wie in der Notenansicht).
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
      child: Focus(autofocus: true, child: _scaffold(context, theme, setlist)),
    );
  }

  Widget _scaffold(BuildContext context, ThemeData theme, bool setlist) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Seitenübersicht', 'Page overview')),
        actions: const [WindowButtons(), SizedBox(width: 8)],
        bottom: !setlist
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: SizedBox(
                  height: 52,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                    itemCount: widget.titles.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, i) => ChoiceChip(
                      label: Text('${i + 1}. ${widget.titles[i]}'),
                      selected: i == _piece,
                      onSelected: (_) => setState(() => _piece = i),
                    ),
                  ),
                ),
              ),
      ),
      body: FutureBuilder<OverviewPiece?>(
        key: ValueKey(_piece),
        future: _pieceAt(_piece),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final p = snap.data;
          if (p == null) {
            return Center(child: Text(tr('Das Stück liess sich nicht öffnen.', 'The piece could not be opened.')));
          }
          return LayoutBuilder(
            builder: (context, box) {
              final cols = math.max(2, (box.maxWidth / _tileWidth).floor());
              const pad = 16.0, gap = 14.0, labelH = 26.0;
              final tileW = (box.maxWidth - 2 * pad - (cols - 1) * gap) / cols;
              final tileH = tileW * 1.414 + labelH;
              // Zur aktuellen Seite scrollen (nur beim aktuellen Stück).
              final current = _piece == widget.currentPiece && widget.currentPages.isNotEmpty
                  ? widget.currentPages.reduce(math.min) - 1
                  : 0;
              final row = current ~/ cols;
              final offset = math.max(0.0, row * (tileH + gap) - box.maxHeight / 3);
              if (_scrollPiece != _piece) {
                final old = _scroll;
                WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
                _scroll = ScrollController(initialScrollOffset: offset);
                _scrollPiece = _piece;
              }
              return GridView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(pad),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: gap,
                  crossAxisSpacing: gap,
                  mainAxisExtent: tileH,
                ),
                itemCount: p.piece.pages.length,
                itemBuilder: (context, i) {
                  final here = _piece == widget.currentPiece && widget.currentPages.contains(i + 1);
                  return _Tile(
                    image: _thumb(_piece, i),
                    number: i + 1,
                    current: here,
                    labelHeight: labelH,
                    onTap: () => Navigator.of(context).pop((piece: _piece, page: i + 1)),
                    style: theme.textTheme.labelLarge,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.image,
    required this.number,
    required this.current,
    required this.labelHeight,
    required this.onTap,
    this.style,
  });
  final ValueNotifier<ui.Image?> image;
  final int number;
  final bool current;
  final double labelHeight;
  final VoidCallback onTap;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: current ? scheme.primary : Colors.transparent, width: 3),
              ),
              padding: const EdgeInsets.all(4),
              child: ValueListenableBuilder<ui.Image?>(
                valueListenable: image,
                builder: (context, img, _) => img == null
                    ? const Center(
                        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : RawImage(image: img, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
              ),
            ),
          ),
          SizedBox(
            height: labelHeight,
            child: Center(
              child: Text(
                '$number',
                style: style?.copyWith(
                  color: current ? scheme.primary : null,
                  fontWeight: current ? FontWeight.w700 : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
