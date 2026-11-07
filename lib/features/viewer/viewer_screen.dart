import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../app/theme.dart';
import '../../core/pdf/page_image_cache.dart';
import 'ink_controller.dart';
import 'ink_layer.dart';
import 'pen_diagnostics.dart';

/// Zeigt ein Notenstück seitenweise an – mit Umblättern per Pedal,
/// Tastatur oder Antippen und mit Stift-Anmerkungen.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, required this.pdfPath});
  final String pdfPath;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  PdfDocument? _doc;
  PageImageCache? _cache;
  late final InkController _ink = InkController(pdfPath: widget.pdfPath);
  final _diagnostics = PenDiagnostics();
  bool _showDiagnostics = false;
  String? _error;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final doc = await PdfDocument.openFile(widget.pdfPath);
      await _ink.load();
      if (!mounted) {
        await doc.dispose();
        return;
      }
      setState(() {
        _doc = doc;
        _cache = PageImageCache(doc);
      });
    } catch (e) {
      setState(() => _error = 'Die Datei konnte nicht geöffnet werden.\n$e');
    }
  }

  @override
  void dispose() {
    _ink.dispose(); // speichert offene Änderungen
    _cache?.dispose();
    _doc?.dispose();
    _diagnostics.dispose();
    super.dispose();
  }

  int get _pageCount => _cache?.pageCount ?? 0;

  void _goTo(int page) {
    if (_pageCount == 0) return;
    final target = page.clamp(1, _pageCount);
    if (target != _page) setState(() => _page = target);
  }

  void _toggleDiagnostics() => setState(() => _showDiagnostics = !_showDiagnostics);

  void _next() => _goTo(_page + 1);
  void _prev() => _goTo(_page - 1);

  // ---------------------------------------------------------------- Tastatur
  // Bluetooth-Pedale wie das iRig BlueTurn senden je nach Modus Pfeiltasten
  // oder "Bild auf/ab". Alle Varianten blättern.
  static final _nextKeys = {
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.pageDown,
    LogicalKeyboardKey.space,
  };
  static final _prevKeys = {
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.pageUp,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    if (_nextKeys.contains(key)) {
      _next();
    } else if (_prevKeys.contains(key)) {
      _prev();
    } else if (key == LogicalKeyboardKey.home) {
      _goTo(1);
    } else if (key == LogicalKeyboardKey.end) {
      _goTo(_pageCount);
    } else if (ctrl && key == LogicalKeyboardKey.keyZ) {
      shift ? _ink.redo() : _ink.undo();
    } else if (ctrl && key == LogicalKeyboardKey.keyY) {
      _ink.redo();
    } else if (event is KeyDownEvent && key == LogicalKeyboardKey.keyP) {
      _ink.setMode(ToolMode.pen);
    } else if (event is KeyDownEvent && key == LogicalKeyboardKey.keyH) {
      _ink.setMode(ToolMode.highlighter);
    } else if (event is KeyDownEvent && key == LogicalKeyboardKey.keyE) {
      _ink.setMode(ToolMode.eraser);
    } else if (key == LogicalKeyboardKey.escape) {
      if (_ink.mode != ToolMode.read) {
        _ink.setMode(ToolMode.read);
      } else {
        Navigator.of(context).maybePop();
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ---------------------------------------------------------------- Aufbau
  @override
  Widget build(BuildContext context) {
    final title = p.basenameWithoutExtension(widget.pdfPath);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: VoltiColors.pageSurround(context),
        body: SafeArea(
          child: Column(children: [
            // ExcludeFocus: Buttons sollen nie den Tastatur-Fokus "stehlen",
            // sonst würde z. B. die Leertaste eines Pedals einen Button auslösen.
            ExcludeFocus(child: _Toolbar(state: this, title: title)),
            Expanded(child: _buildPageArea()),
          ]),
        ),
      ),
    );
  }

  Widget _buildPageArea() {
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)));
    }
    final cache = _cache;
    if (cache == null) return const Center(child: CircularProgressIndicator());

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _diagnostics.record,
      onPointerMove: _diagnostics.record,
      onPointerHover: _showDiagnostics ? _diagnostics.record : null,
      onPointerUp: _diagnostics.record,
      child: Stack(children: [
        Positioned.fill(
          child: ListenableBuilder(
            listenable: _ink,
            builder: (context, _) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Antippen blättert nur im Lese-Modus. Beim Zeichnen würde ein
              // Punkt mit dem Stift sonst ungewollt umblättern.
              onTapUp: _ink.mode == ToolMode.read ? _onTap : null,
              onHorizontalDragEnd: _ink.mode == ToolMode.read ? _onSwipe : null,
              child: LayoutBuilder(builder: (context, box) => _buildPage(cache, box)),
            ),
          ),
        ),
        if (_showDiagnostics)
          Positioned(right: 12, bottom: 12, child: IgnorePointer(child: PenDiagnosticsPanel(diagnostics: _diagnostics))),
        if (_ink.saveError != null)
          Positioned(
            left: 12,
            bottom: 12,
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
              child: Padding(padding: const EdgeInsets.all(8), child: Text(_ink.saveError!)),
            ),
          ),
      ]),
    );
  }

  void _onTap(TapUpDetails d) {
    if (d.kind == PointerDeviceKind.invertedStylus) return;
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 1;
    // Linkes Drittel: zurück. Rest: vorwärts.
    d.globalPosition.dx < width * 0.33 ? _prev() : _next();
  }

  void _onSwipe(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v < -300) _next();
    if (v > 300) _prev();
  }

  Widget _buildPage(PageImageCache cache, BoxConstraints box) {
    const margin = 8.0;
    final availW = box.maxWidth - 2 * margin;
    final availH = box.maxHeight - 2 * margin;
    final aspect = cache.aspectRatio(_page);
    final w = availW / availH > aspect ? availH * aspect : availW;
    final h = w / aspect;

    // In 128-Pixel-Schritten rendern, damit nicht jede kleine
    // Fensteränderung ein neues Rendern auslöst.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final pixelWidth = ((w * dpr / 128).ceil() * 128).clamp(128, 4096);

    cache.setVisiblePages({_page});
    cache.preload([_page + 1, _page + 2, _page - 1], pixelWidth);

    return Center(
      child: SizedBox(
        width: w,
        height: h,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))],
          ),
          child: Stack(fit: StackFit.expand, children: [
            ListenableBuilder(
              listenable: cache,
              builder: (context, _) {
                final img = cache.imageFor(_page, pixelWidth);
                return img == null
                    ? const SizedBox.shrink()
                    : RawImage(image: img, fit: BoxFit.fill, filterQuality: FilterQuality.medium);
              },
            ),
            // Im Lese-Modus reagiert die Stift-Ebene nur auf das Radierer-Ende.
            InkLayer(key: ValueKey(_page), page: _page, controller: _ink),
          ]),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.state, required this.title});
  final _ViewerScreenState state;
  final String title;

  static const _penColors = <(int, String)>[
    (0xFF1B1B1B, 'Schwarz'),
    (0xFFC62828, 'Rot'),
    (0xFF1565C0, 'Blau'),
    (0xFF2E7D32, 'Grün'),
  ];

  @override
  Widget build(BuildContext context) {
    final ink = state._ink;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 1,
      child: SizedBox(
        height: 52,
        child: ListenableBuilder(
          listenable: ink,
          builder: (context, _) {
            Widget tool(ToolMode m, IconData icon, String tip) => IconButton(
                  tooltip: tip,
                  isSelected: ink.mode == m,
                  icon: Icon(icon),
                  style: IconButton.styleFrom(
                    backgroundColor: ink.mode == m ? scheme.primaryContainer : null,
                    foregroundColor: ink.mode == m ? scheme.onPrimaryContainer : null,
                  ),
                  onPressed: () => ink.setMode(m),
                );
            return Row(children: [
              IconButton(
                tooltip: 'Zurück zur Bibliothek',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Text(title, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
              ),
              Flexible(
                flex: 3,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(children: [
                    tool(ToolMode.read, Icons.chrome_reader_mode_outlined, 'Lesen (Esc)'),
                    tool(ToolMode.pen, Icons.edit, 'Stift (P)'),
                    tool(ToolMode.highlighter, Icons.border_color, 'Textmarker (H)'),
                    tool(ToolMode.eraser, Icons.auto_fix_normal, 'Radierer (E)'),
                    if (ink.mode == ToolMode.pen) ...[
                      const SizedBox(width: 4),
                      for (final (color, name) in _penColors)
                        _ColorDot(
                          color: Color(color),
                          name: name,
                          selected: ink.penColor == color,
                          onTap: () => ink.setPenColor(color),
                        ),
                    ],
                    const _Divider(),
                    IconButton(
                      tooltip: 'Rückgängig (Strg+Z)',
                      icon: const Icon(Icons.undo),
                      onPressed: ink.canUndo ? ink.undo : null,
                    ),
                    IconButton(
                      tooltip: 'Wiederholen (Strg+Y)',
                      icon: const Icon(Icons.redo),
                      onPressed: ink.canRedo ? ink.redo : null,
                    ),
                    const _Divider(),
                    IconButton(
                      tooltip: 'Stift-Test anzeigen',
                      isSelected: state._showDiagnostics,
                      icon: const Icon(Icons.sensors),
                      onPressed: state._toggleDiagnostics,
                    ),
                    const _Divider(),
                    IconButton(tooltip: 'Vorherige Seite', icon: const Icon(Icons.chevron_left), onPressed: state._prev),
                    Text(
                      state._pageCount == 0 ? '–' : '${state._page} / ${state._pageCount}',
                      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                    IconButton(tooltip: 'Nächste Seite', icon: const Icon(Icons.chevron_right), onPressed: state._next),
                    const SizedBox(width: 4),
                  ]),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.name, required this.selected, required this.onTap});
  final Color color;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: name,
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        child: Container(
          width: 26,
          height: 26,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
              width: 3,
              strokeAlign: BorderSide.strokeAlignOutside,
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 6), color: Theme.of(context).dividerColor);
}
