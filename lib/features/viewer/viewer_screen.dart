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
import '../../core/ink/selection.dart';
import 'layers_dialog.dart';
import 'page_flow.dart';
import 'pen_diagnostics.dart';
import 'ruler_overlay.dart';
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

/// Ein geöffnetes Stück: PDF, Seitenbilder und Anmerkungen.
class _Piece {
  _Piece(this.item) : ink = InkController(pdfPath: item.path);

  final ViewerItem item;
  final InkController ink;
  PdfDocument? doc;
  PageImageCache? cache;
  String? error;
  late final Future<void> ready = _load();

  int? get pageCount => cache?.pageCount ?? (error != null ? 0 : null);

  Future<void> _load() async {
    try {
      final d = await PdfDocument.openFile(item.path);
      await ink.load();
      doc = d;
      cache = PageImageCache(d);
    } catch (e) {
      error = 'Die Datei konnte nicht geöffnet werden.\n${item.path}\n\n$e';
    }
  }

  void dispose() {
    ink.dispose(); // speichert offene Änderungen
    cache?.dispose();
    doc?.dispose();
  }
}

class _ViewerScreenState extends State<ViewerScreen> {
  /// Geöffnete Stücke (das aktuelle und die Nachbarn).
  final Map<int, _Piece> _pieces = {};

  /// Linke (bzw. einzige) sichtbare Seite.
  late PageSlot _left = PageSlot(widget.startIndex.clamp(0, widget.items.length - 1), 1);

  /// Zuletzt berührte Seite – für Rückgängig und "Seite leeren".
  PageSlot? _activeSlot;

  /// Wird gerade die Doppelseite gezeigt? (Ergibt sich aus Fenster und Einstellung.)
  bool _twoUp = false;

  final _diagnostics = PenDiagnostics();
  bool _showDiagnostics = false;

  /// Wird gerade eine Text-Notiz getippt? Dann blättern Tasten nicht um.
  bool _editingText = false;

  /// Leiste oben/unten sichtbar (in der Spielansicht nur kurz).
  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _fullscreen = false;
  PointerDeviceKind? _dragKind;
  int? _reportedPiece;

  ToolController get tools => widget.tools;
  bool get _isSetlist => widget.items.length > 1;

  late final _flow = PageFlow(pieceCount: widget.items.length, pageCount: (i) => _pieces[i]?.pageCount);

  // Für Leisten und Titel: das Stück der linken Seite.
  int get _index => _left.piece;
  int get _page => _left.page;
  ViewerItem get _item => widget.items[_left.piece];
  _Piece? get _leftPiece => _pieces[_left.piece];
  int get _pageCount => _leftPiece?.pageCount ?? 0;
  PageSlot? get _right => _twoUp ? _flow.rightOf(_left) : null;

  /// z. B. "Seite 3 von 8", "Seiten 3–4 von 8" oder "Seite 8 · rechts: Ave Maria".
  String get _pageLabel {
    final r = _right;
    if (r == null) return 'Seite ${_left.page} von $_pageCount';
    if (r.piece == _left.piece) return 'Seiten ${_left.page}–${r.page} von $_pageCount';
    return 'Seite ${_left.page} von $_pageCount · rechts: ${widget.items[r.piece].title}';
  }

  _Piece get _activePiece => _pieces[(_activeSlot ?? _left).piece] ?? _leftPiece!;
  int get _activePage => (_activeSlot ?? _left).page;

  @override
  void initState() {
    super.initState();
    tools.setMode(ToolMode.read);
    tools.addListener(_onToolsChanged);
    _ensureAround(_left.piece);
    _restartHideTimer();
  }

  ToolMode? _lastMode;
  bool? _lastPaletteLeft;
  PageLayout? _lastLayout;
  bool? _lastRuler;

  /// Die ganze Ansicht nur neu aufbauen, wenn sich das Werkzeug wechselt –
  /// nicht bei jeder Bewegung eines Reglers im Einstellungsfenster.
  void _onToolsChanged() {
    if (!mounted) return;
    if (tools.mode != _lastMode ||
        tools.paletteLeft != _lastPaletteLeft ||
        tools.pageLayout != _lastLayout ||
        tools.rulerVisible != _lastRuler) {
      _lastRuler = tools.rulerVisible;
      _lastMode = tools.mode;
      _lastPaletteLeft = tools.paletteLeft;
      _lastLayout = tools.pageLayout;
      setState(() {});
    }
  }

  /// Lädt ein Stück (einmalig) und baut danach neu auf.
  Future<_Piece> _ensure(int i) {
    final p = _pieces.putIfAbsent(i, () => _Piece(widget.items[i]));
    return p.ready.then((_) {
      if (mounted) setState(() {});
      return p;
    });
  }

  /// Das aktuelle Stück und seine Nachbarn bereithalten (für das Blättern
  /// über Songgrenzen und die rechte Seite der Doppelansicht).
  void _ensureAround(int i) {
    for (final j in [i, i + 1, i - 1, i + 2]) {
      if (j >= 0 && j < widget.items.length) _ensure(j);
    }
    // Weiter entfernte Stücke freigeben (speichert deren Anmerkungen).
    final far = _pieces.keys.where((k) => k < i - 1 || k > i + 2).toList();
    if (far.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final k in far) {
        if (k >= _left.piece - 1 && k <= _left.piece + 2) continue;
        _pieces.remove(k)?.dispose();
      }
    });
  }

  /// Alles auf der zuletzt berührten Seite auswählen (Strg+A).
  void _selectAll() {
    final ink = _activePiece.ink, page = _activePage;
    final a = ink.annotations;
    final ids = SelectionIds(
      strokes: {for (final s in a.visibleStrokesOn(page)) s.id},
      stamps: {for (final s in a.visibleStampsOn(page)) s.id},
      texts: {for (final t in a.visibleTextsOn(page)) t.id},
    );
    if (ids.isEmpty) return;
    tools.setMode(ToolMode.lasso);
    tools.select(InkSelection(ink, page, ids));
  }

  void _show(PageSlot slot) {
    if (slot == _left) return;
    // Eine Auswahl auf einer Seite, die man nicht mehr sieht, wäre gefährlich
    // (z. B. Entf-Taste) – also aufheben. Die Zwischenablage bleibt.
    tools.clearSelection();
    setState(() {
      _left = slot;
      _activeSlot = null;
    });
    _ensureAround(slot.piece);
  }

  void _reportOpened() {
    final p = _leftPiece;
    if (p == null || p.doc == null || _reportedPiece == _left.piece) return;
    _reportedPiece = _left.piece;
    widget.onOpened?.call(p.item.path);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    tools.removeListener(_onToolsChanged);
    tools.setMode(ToolMode.read);
    if (_fullscreen) setAppFullscreen(false);
    for (final p in _pieces.values) {
      p.dispose();
    }
    _diagnostics.dispose();
    super.dispose();
  }

  /// Seite im aktuellen Stück (Regler, Pos1/Ende).
  void _goTo(int page) {
    if (_pageCount == 0) return;
    _show(PageSlot(_left.piece, page.clamp(1, _pageCount)));
  }

  /// Springt an den Anfang eines Stücks der Setlist.
  void _openPiece(int index) => _show(PageSlot(index, 1));

  Future<void> _next() async {
    // Für das Blättern über die Songgrenze muss das nächste Stück bereit sein.
    if (_left.piece + 1 < widget.items.length) await _ensure(_left.piece + 1);
    if (_twoUp && _left.piece + 2 < widget.items.length) await _ensure(_left.piece + 2);
    if (!mounted) return;
    final target = _flow.next(_left, twoUp: _twoUp);
    if (target != null) _show(target);
  }

  Future<void> _prev() async {
    if (_left.piece > 0) await _ensure(_left.piece - 1);
    if (!mounted) return;
    final target = _flow.previous(_left, twoUp: _twoUp);
    if (target != null) _show(target);
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

  /// Vollbild von Hand: F11, Esc oder das Symbol in der Leiste.
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
    } else if (ctrl && key == LogicalKeyboardKey.keyC) {
      tools.copySelection();
    } else if (ctrl && key == LogicalKeyboardKey.keyX) {
      tools.cutSelection();
    } else if (ctrl && key == LogicalKeyboardKey.keyV) {
      tools.pasteInto(_activePiece.ink, _activePage);
    } else if (ctrl && key == LogicalKeyboardKey.keyD) {
      tools.duplicateSelection();
    } else if (ctrl && key == LogicalKeyboardKey.keyA) {
      _selectAll();
    } else if ((key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) &&
        tools.selection.value != null) {
      tools.deleteSelection();
    } else if (ctrl && key == LogicalKeyboardKey.keyZ) {
      shift ? _activePiece.ink.redo() : _activePiece.ink.undo();
    } else if (ctrl && key == LogicalKeyboardKey.keyY) {
      _activePiece.ink.redo();
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
    } else if (down && key == LogicalKeyboardKey.keyS) {
      tools.setMode(ToolMode.stamp);
    } else if (down && key == LogicalKeyboardKey.keyF) {
      tools.setMode(ToolMode.shape);
    } else if (down && !ctrl && key == LogicalKeyboardKey.keyA) {
      tools.setMode(ToolMode.lasso);
    } else if (down && key == LogicalKeyboardKey.keyL) {
      tools.toggleRuler();
    } else if (down && _digits.contains(key)) {
      tools.applyFavoriteIndex(_digits.indexOf(key));
    } else if (key == LogicalKeyboardKey.escape) {
      if (tools.selection.value != null) {
        tools.clearSelection();
      } else if (tools.editing) {
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
    // Doppelseite: im Querformat automatisch (oder fest eingestellt). Schon
    // hier bestimmen, damit Leisten und Seiten dasselbe anzeigen.
    final screen = MediaQuery.sizeOf(context);
    final layout = tools.pageLayout;
    _twoUp = layout == PageLayout.double || (layout == PageLayout.auto && screen.width > screen.height * 1.05);
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
                child: RepaintBoundary(
                  child: _Slide(
                    visible: showBars,
                    fromTop: true,
                    child: _TopBar(state: this),
                  ),
                ),
              ),
            ),
            if (_pageCount > 1)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ExcludeFocus(
                  child: RepaintBoundary(
                    child: _Slide(
                      visible: showBars,
                      fromTop: false,
                      child: _PageBar(state: this),
                    ),
                  ),
                ),
              ),
            // Lineal über den Noten (unter der Werkzeugleiste).
            if (tools.rulerVisible && _leftPiece?.cache != null) Positioned.fill(child: RulerOverlay(tools: tools)),
            if (editing && _leftPiece?.cache != null)
              Positioned.fill(
                child: SafeArea(
                  // TextFieldTapRegion: Antippen des Einstellungsfensters beendet
                  // das Schreiben einer Text-Notiz nicht.
                  child: ExcludeFocus(
                    child: TextFieldTapRegion(
                      child: ToolOverlay(tools: tools, ink: _activePiece.ink, page: _activePage),
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
            if (_leftPiece?.ink.saveError != null)
              Positioned(
                left: 12,
                bottom: 12,
                child: Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(padding: const EdgeInsets.all(8), child: Text(_leftPiece!.ink.saveError!)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageArea() {
    final left = _leftPiece;
    if (left == null || left.pageCount == null) return const Center(child: CircularProgressIndicator());
    final reading = tools.mode == ToolMode.read;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportOpened());

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
        child: SafeArea(child: LayoutBuilder(builder: (context, box) => _buildPages(box))),
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

  /// Eine oder zwei Seiten, so gross wie möglich.
  Widget _buildPages(BoxConstraints box) {
    const margin = 6.0, gap = 8.0;
    final availW = box.maxWidth - 2 * margin;
    final availH = box.maxHeight - 2 * margin;
    final slots = [_left, ?_right];
    double aspectOf(PageSlot s) {
      final c = _pieces[s.piece]?.cache;
      return c == null ? (_leftPiece?.cache?.aspectRatio(_left.page) ?? 0.707) : c.aspectRatio(s.page);
    }

    final aspects = [for (final s in slots) aspectOf(s)];
    final totalAspect = aspects.reduce((a, b) => a + b);
    final gaps = gap * (slots.length - 1);
    final h = ((availW - gaps) / availH > totalAspect ? availH : (availW - gaps) / totalAspect);

    // Sichtbare Seiten nicht aus dem Zwischenspeicher verdrängen; die
    // nächsten Seiten schon vorbereiten, damit das Umblättern sofort geht.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final visibleByPiece = <int, Set<int>>{};
    for (final s in slots) {
      (visibleByPiece[s.piece] ??= {}).add(s.page);
    }
    for (final e in visibleByPiece.entries) {
      _pieces[e.key]?.cache?.setVisiblePages(e.value);
    }
    final last = slots.last;
    final upcoming = <PageSlot>[];
    var cursor = _flow.after(last);
    for (var i = 0; i < slots.length * 2 && cursor != null; i++) {
      upcoming.add(cursor);
      cursor = _flow.after(cursor);
    }
    final before = _flow.before(_left);
    for (final s in [...upcoming, ?before]) {
      final c = _pieces[s.piece]?.cache;
      if (c == null) continue;
      final w = h * c.aspectRatio(s.page);
      c.preload([s.page], ((w * dpr / 128).ceil() * 128).clamp(128, 4096));
    }

    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, s) in slots.indexed) ...[
            if (i > 0) const SizedBox(width: gap),
            _buildPage(s, h * aspects[i], h, dpr),
          ],
        ],
      ),
    );
  }

  Widget _buildPage(PageSlot slot, double w, double h, double dpr) {
    final piece = _pieces[slot.piece];
    final cache = piece?.cache;
    if (piece == null || cache == null) {
      return SizedBox(
        width: w,
        height: h,
        child: ColoredBox(
          color: Colors.white,
          child: Center(
            child: piece?.error != null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(piece!.error!, textAlign: TextAlign.center),
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      );
    }
    // In 128-Pixel-Schritten rendern, damit nicht jede kleine
    // Fensteränderung ein neues Rendern auslöst.
    final pixelWidth = ((w * dpr / 128).ceil() * 128).clamp(128, 4096);
    final key = '${slot.piece}/${slot.page}';

    // RepaintBoundary: Jede Ebene wird nur neu gemalt, wenn sie sich selbst
    // ändert. Sonst würde z. B. jede Stiftbewegung auch die grosse Notenseite
    // neu malen – das macht das Zeichnen träge.
    // Schlüssel pro Seite: Rutscht beim Blättern die rechte Seite nach links,
    // behält sie ihre fertigen Bilder und muss nichts neu erzeugen.
    return Listener(
      key: ValueKey('page/$key'),
      // Merken, auf welcher Seite zuletzt gearbeitet wurde (Rückgängig, Leeren).
      onPointerDown: (_) {
        if (_activeSlot != slot) setState(() => _activeSlot = slot);
      },
      child: RepaintBoundary(
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Weisse Seite ohne Schatten (ein weicher Schatten kostet beim Malen viel Zeit).
              const ColoredBox(color: Colors.white),
              RepaintBoundary(
                child: ListenableBuilder(
                  listenable: cache,
                  builder: (context, _) {
                    final img = cache.imageFor(slot.page, pixelWidth);
                    return img == null
                        ? const SizedBox.shrink()
                        : RawImage(image: img, fit: BoxFit.fill, filterQuality: FilterQuality.medium);
                  },
                ),
              ),
              InkLayer(key: ValueKey('ink/$key'), page: slot.page, controller: piece.ink, tools: tools),
              RepaintBoundary(
                child: TextNotesLayer(
                  key: ValueKey('text/$key'),
                  page: slot.page,
                  controller: piece.ink,
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
                        state._pageLabel,
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
                        value: () => tools.setInstantPen(!tools.instantPen),
                        checked: tools.instantPen,
                        child: const Text('Mit dem Stift sofort zeichnen'),
                      ),
                      for (final (l, label) in const [
                        (PageLayout.auto, 'Seiten: automatisch (quer = zwei)'),
                        (PageLayout.single, 'Seiten: immer eine'),
                        (PageLayout.double, 'Seiten: immer zwei'),
                      ])
                        CheckedPopupMenuItem(
                          value: () => tools.setPageLayout(l),
                          checked: tools.pageLayout == l,
                          child: Text(label),
                        ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: () => showLayersDialog(context, state._activePiece.ink),
                        child: const ListTile(
                          leading: Icon(Icons.layers_outlined),
                          title: Text('Ebenen …'),
                          contentPadding: EdgeInsets.zero,
                        ),
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
