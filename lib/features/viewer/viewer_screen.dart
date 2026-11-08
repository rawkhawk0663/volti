import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../app/theme.dart';
import '../../core/pdf/page_image_cache.dart';
import 'fullscreen.dart';
import 'ink_controller.dart';
import 'ink_layer.dart';
import 'pen_diagnostics.dart';
import 'text_layer.dart';
import 'tool_controller.dart';
import 'tool_palette.dart';

/// Ein Stück, das im Notenbetrachter angezeigt wird.
class ViewerItem {
  const ViewerItem(this.path, this.title);
  final String path;
  final String title;
}

/// Die Notenansicht.
///
/// **Spielansicht** (Standard): nur die Noten, bildschirmfüllend, auf Wunsch
/// im Vollbild. Rechts tippen oder Pedal = weiter, links = zurück, Mitte =
/// Leiste kurz einblenden. Mit dem Stift ziehen zeichnet sofort.
///
/// **Bearbeiten**: Werkzeug-Palette am Seitenrand.
///
/// Mit mehreren [items] (Setlist) geht es nach der letzten Seite eines
/// Stücks direkt zur ersten Seite des nächsten – und rückwärts genauso.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({
    super.key,
    required this.items,
    required this.tools,
    this.startIndex = 0,
    this.setlistName,
    this.onOpened,
  });

  final List<ViewerItem> items;
  final ToolController tools;
  final int startIndex;
  final String? setlistName;

  /// Wird aufgerufen, sobald ein Stück geöffnet ist (z. B. für "zuletzt geöffnet").
  final void Function(String path)? onOpened;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  PdfDocument? _doc;
  PageImageCache? _cache;
  late InkController _ink;
  final _diagnostics = PenDiagnostics();
  bool _showDiagnostics = false;

  /// Wird gerade eine Text-Notiz getippt? Dann blättern Tasten nicht um.
  bool _editingText = false;
  String? _error;
  int _page = 1;
  late int _index = widget.startIndex.clamp(0, widget.items.length - 1);
  int _loadToken = 0;

  /// Leiste oben/unten sichtbar (in der Spielansicht nur kurz).
  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _fullscreen = false;
  PointerDeviceKind? _dragKind;

  ViewerItem get _item => widget.items[_index];
  bool get _isSetlist => widget.items.length > 1;
  ToolController get tools => widget.tools;

  @override
  void initState() {
    super.initState();
    tools.setMode(ToolMode.read);
    tools.addListener(_onToolsChanged);
    _ink = InkController(pdfPath: _item.path);
    _openPiece(_index);
    // Vollbild erst nach dem Aufbau der Ansicht einschalten – während der
    // Übergangsanimation kommt der Befehl unter Windows sonst nicht an.
    _fullscreen = tools.fullscreen;
    if (_fullscreen) WidgetsBinding.instance.addPostFrameCallback((_) => _enterFullscreenReliably());
    _restartHideTimer();
  }

  ToolMode? _lastMode;
  bool? _lastPaletteLeft;

  /// Die ganze Ansicht nur neu aufbauen, wenn sich das Werkzeug wechselt –
  /// nicht bei jeder Bewegung eines Reglers im Einstellungsfenster.
  void _onToolsChanged() {
    if (!mounted) return;
    if (tools.mode != _lastMode || tools.paletteLeft != _lastPaletteLeft) {
      _lastMode = tools.mode;
      _lastPaletteLeft = tools.paletteLeft;
      setState(() {});
    }
  }

  /// Öffnet ein Stück der Liste. [atEnd]: auf der letzten Seite beginnen
  /// (beim Zurückblättern aus dem nächsten Stück).
  Future<void> _openPiece(int index, {bool atEnd = false}) async {
    final token = ++_loadToken;
    final item = widget.items[index];
    final ink = InkController(pdfPath: item.path);
    PdfDocument? doc;
    String? error;
    try {
      doc = await PdfDocument.openFile(item.path);
      await ink.load();
    } catch (e) {
      error = 'Die Datei konnte nicht geöffnet werden.\n${item.path}\n\n$e';
    }
    if (!mounted || token != _loadToken) {
      await doc?.dispose();
      ink.dispose();
      return;
    }
    final oldDoc = _doc, oldCache = _cache, oldInk = _ink;
    setState(() {
      _index = index;
      _doc = doc;
      _cache = doc == null ? null : PageImageCache(doc);
      _ink = ink;
      _error = error;
      _page = atEnd && doc != null ? doc.pages.length : 1;
    });
    // Alte Daten erst nach dem nächsten Bild freigeben.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldInk.dispose(); // speichert offene Änderungen
      oldCache?.dispose();
      oldDoc?.dispose();
    });
    if (doc != null) widget.onOpened?.call(item.path);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    tools.removeListener(_onToolsChanged);
    tools.setMode(ToolMode.read);
    if (_fullscreen) setAppFullscreen(false);
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

  void _next() {
    if (_page < _pageCount) {
      _goTo(_page + 1);
    } else if (_index < widget.items.length - 1) {
      _openPiece(_index + 1);
    }
  }

  void _prev() {
    if (_page > 1) {
      _goTo(_page - 1);
    } else if (_index > 0) {
      _openPiece(_index - 1, atEnd: true);
    }
  }

  // --------------------------------------------------- Leiste und Vollbild
  void _showControlsBriefly() {
    setState(() => _controlsVisible = true);
    _restartHideTimer();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControlsBriefly();
    }
  }

  Future<void> _setFullscreen(bool on) async {
    setState(() => _fullscreen = on);
    await setAppFullscreen(on);
  }

  /// Schaltet das Vollbild nach dem Aufbau der Ansicht ein.
  Future<void> _enterFullscreenReliably() async {
    if (!mounted || !_fullscreen) return;
    await setAppFullscreen(true);
  }

  /// F11, Esc oder Symbol: nur für den Moment. Ob Stücke im Vollbild
  /// öffnen, ist eine eigene Einstellung (⋮-Menü).
  Future<void> _toggleFullscreen() => _setFullscreen(!_fullscreen);

  void _toggleDiagnostics() => setState(() => _showDiagnostics = !_showDiagnostics);

  // ---------------------------------------------------------------- Tastatur
  // Bluetooth-Pedale wie das iRig BlueTurn senden je nach Modus Pfeiltasten
  // oder "Bild auf/ab". Alle Varianten blättern.
  static final _nextKeys = {
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.pageDown,
    LogicalKeyboardKey.space,
  };
  static final _prevKeys = {LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.pageUp};
  static final _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || _editingText) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final down = event is KeyDownEvent;

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
    } else if (down && key == LogicalKeyboardKey.f11) {
      _toggleFullscreen();
    } else if (down && key == LogicalKeyboardKey.keyP) {
      tools.setMode(ToolMode.pen);
    } else if (down && key == LogicalKeyboardKey.keyH) {
      tools.setMode(ToolMode.highlighter);
    } else if (down && key == LogicalKeyboardKey.keyE) {
      tools.setMode(ToolMode.eraser);
    } else if (down && key == LogicalKeyboardKey.keyT) {
      tools.setMode(ToolMode.text);
    } else if (down && _digits.contains(key)) {
      tools.applyFavoriteIndex(_digits.indexOf(key));
    } else if (key == LogicalKeyboardKey.escape) {
      if (tools.editing) {
        tools.finishEditing();
      } else if (_fullscreen) {
        _toggleFullscreen();
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
    final editing = tools.editing;
    final showBars = _controlsVisible && !editing;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: VoltiColors.pageSurround(context),
        body: Stack(
          children: [
            Positioned.fill(child: _buildPageArea()),
            // Am Computer: Maus an den oberen Rand → Leiste erscheint.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 10,
              child: MouseRegion(opaque: false, onEnter: (_) => editing ? null : _showControlsBriefly()),
            ),
            // ExcludeFocus: Buttons sollen nie den Tastatur-Fokus "stehlen",
            // sonst würde z. B. die Leertaste eines Pedals einen Button auslösen.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ExcludeFocus(
                child: _Slide(
                  visible: showBars,
                  fromTop: true,
                  child: _TopBar(state: this),
                ),
              ),
            ),
            if (_pageCount > 1)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ExcludeFocus(
                  child: _Slide(
                    visible: showBars,
                    fromTop: false,
                    child: _PageBar(state: this),
                  ),
                ),
              ),
            if (editing && _cache != null)
              Positioned.fill(
                child: SafeArea(
                  // TextFieldTapRegion: Antippen des Einstellungsfensters beendet
                  // das Schreiben einer Text-Notiz nicht.
                  child: ExcludeFocus(
                    child: TextFieldTapRegion(
                      child: ToolOverlay(tools: tools, ink: _ink, page: _page),
                    ),
                  ),
                ),
              ),
            if (_showDiagnostics)
              Positioned(
                right: 12,
                bottom: 72,
                child: IgnorePointer(child: PenDiagnosticsPanel(diagnostics: _diagnostics)),
              ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildPageArea() {
    if (_error != null) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Zurück')),
              ],
            ),
          ),
        ),
      );
    }
    final cache = _cache;
    if (cache == null) return const Center(child: CircularProgressIndicator());
    final reading = tools.mode == ToolMode.read;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _diagnostics.record,
      onPointerMove: _diagnostics.record,
      onPointerHover: _showDiagnostics ? _diagnostics.record : null,
      onPointerUp: _diagnostics.record,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Antippen und Wischen gelten nur in der Spielansicht. Beim Bearbeiten
        // würde ein Punkt mit dem Stift sonst ungewollt umblättern.
        onTapUp: reading ? _onTap : null,
        onHorizontalDragStart: reading ? (d) => _dragKind = d.kind : null,
        onHorizontalDragEnd: reading ? _onSwipe : null,
        child: SafeArea(child: LayoutBuilder(builder: (context, box) => _buildPage(cache, box))),
      ),
    );
  }

  /// Linkes Drittel: zurück. Rechtes Drittel: weiter. Mitte: Leiste ein/aus.
  void _onTap(TapUpDetails d) {
    if (d.kind == PointerDeviceKind.invertedStylus) return;
    final width = MediaQuery.sizeOf(context).width;
    final x = d.globalPosition.dx / width;
    if (x < 0.3) {
      _prev();
    } else if (x > 0.7) {
      _next();
    } else {
      _toggleControls();
    }
  }

  void _onSwipe(DragEndDetails d) {
    // Mit dem Stift wird gezeichnet, nicht geblättert.
    if (_dragKind == PointerDeviceKind.stylus || _dragKind == PointerDeviceKind.invertedStylus) return;
    final v = d.primaryVelocity ?? 0;
    if (v < -300) _next();
    if (v > 300) _prev();
  }

  Widget _buildPage(PageImageCache cache, BoxConstraints box) {
    const margin = 6.0;
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

    // RepaintBoundary: Jede Ebene wird nur neu gemalt, wenn sie sich selbst
    // ändert. Sonst würde z. B. jede Stiftbewegung auch die grosse Notenseite
    // samt Schatten neu malen – das macht das Zeichnen träge.
    return Center(
      child: RepaintBoundary(
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const RepaintBoundary(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))],
                  ),
                ),
              ),
              RepaintBoundary(
                child: ListenableBuilder(
                  listenable: cache,
                  builder: (context, _) {
                    final img = cache.imageFor(_page, pixelWidth);
                    return img == null
                        ? const SizedBox.shrink()
                        : RawImage(image: img, fit: BoxFit.fill, filterQuality: FilterQuality.medium);
                  },
                ),
              ),
              InkLayer(key: ValueKey('$_index/$_page'), page: _page, controller: _ink, tools: tools),
              RepaintBoundary(
                child: TextNotesLayer(
                  key: ValueKey('text/$_index/$_page'),
                  page: _page,
                  controller: _ink,
                  tools: tools,
                  onEditingChanged: (v) => setState(() => _editingText = v),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Blendet eine Leiste weich ein und aus (gleitet vom Rand herein).
class _Slide extends StatelessWidget {
  const _Slide({required this.visible, required this.fromTop, required this.child});
  final bool visible;
  final bool fromTop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : Offset(0, fromTop ? -1 : 1),
        child: AnimatedOpacity(duration: const Duration(milliseconds: 220), opacity: visible ? 1 : 0, child: child),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.state});
  final _ViewerScreenState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tools = state.tools;
    return Listener(
      // Jede Berührung der Leiste hält sie offen.
      onPointerDown: (_) => state._restartHideTimer(),
      child: Material(
        color: scheme.surface,
        elevation: 2,
        child: Ink(
          decoration: BoxDecoration(gradient: VoltiColors.barGradient(Theme.of(context).brightness)),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Zurück zur Bibliothek',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(child: _TitleArea(state: state)),
                  if (state._pageCount > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Seite ${state._page} von ${state._pageCount}',
                        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ),
                  FilledButton.tonalIcon(
                    onPressed: tools.startEditing,
                    icon: const Icon(Icons.edit),
                    label: const Text('Bearbeiten'),
                  ),
                  IconButton(
                    tooltip: state._fullscreen ? 'Vollbild beenden (F11)' : 'Vollbild (F11)',
                    icon: Icon(state._fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
                    onPressed: state._toggleFullscreen,
                  ),
                  PopupMenuButton<VoidCallback>(
                    tooltip: 'Mehr',
                    icon: const Icon(Icons.more_vert),
                    onSelected: (a) => a(),
                    itemBuilder: (_) => [
                      CheckedPopupMenuItem(
                        value: () => tools.setFullscreen(!tools.fullscreen),
                        checked: tools.fullscreen,
                        child: const Text('Noten im Vollbild öffnen'),
                      ),
                      CheckedPopupMenuItem(
                        value: () => tools.setInstantPen(!tools.instantPen),
                        checked: tools.instantPen,
                        child: const Text('Mit dem Stift sofort zeichnen'),
                      ),
                      CheckedPopupMenuItem(
                        value: state._toggleDiagnostics,
                        checked: state._showDiagnostics,
                        child: const Text('Stift-Test anzeigen'),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Unten: Seitenregler zum schnellen Springen.
class _PageBar extends StatelessWidget {
  const _PageBar({required this.state});
  final _ViewerScreenState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = state._pageCount;
    return Listener(
      onPointerDown: (_) => state._restartHideTimer(),
      child: SafeArea(
        top: false,
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 620),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Material(
              elevation: 2,
              color: scheme.surface,
              borderRadius: BorderRadius.circular(28),
              clipBehavior: Clip.antiAlias,
              child: Ink(
                decoration: BoxDecoration(gradient: VoltiColors.barGradient(Theme.of(context).brightness)),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Vorherige Seite',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: state._prev,
                    ),
                    Expanded(
                      child: Slider(
                        min: 1,
                        max: count.toDouble(),
                        divisions: count - 1,
                        value: state._page.toDouble().clamp(1, count.toDouble()),
                        label: 'Seite ${state._page}',
                        onChanged: (v) => state._goTo(v.round()),
                      ),
                    ),
                    IconButton(tooltip: 'Nächste Seite', icon: const Icon(Icons.chevron_right), onPressed: state._next),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Titel des Stücks; in einer Setlist zusätzlich "Stück 2/5" mit
/// Auswahlmenü zum Springen.
class _TitleArea extends StatelessWidget {
  const _TitleArea({required this.state});
  final _ViewerScreenState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = Text(state._item.title, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium);
    if (!state._isSetlist) return title;
    final items = state.widget.items;
    return PopupMenuButton<int>(
      tooltip: 'Stück wählen',
      onSelected: state._openPiece,
      itemBuilder: (_) => [
        for (var i = 0; i < items.length; i++)
          CheckedPopupMenuItem(value: i, checked: i == state._index, child: Text('${i + 1}. ${items[i].title}')),
      ],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          Text(
            '${state.widget.setlistName ?? 'Setlist'} · Stück ${state._index + 1}/${items.length}  ▾',
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }
}
