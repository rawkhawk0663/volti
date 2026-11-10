import 'dart:math' as math;
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
import '../../core/library/page_setup.dart';
import '../../core/library/sidecar_store.dart';
import 'cropped_page.dart';
import '../../core/ink/navigation_marks.dart';
import 'bookmarks_sheet.dart';
import 'export_dialog.dart';
import 'page_export.dart';
import 'reflow_screen.dart';
import 'links_layer.dart';
import 'page_flow.dart';
import 'page_setup_screen.dart';
import 'pen_diagnostics.dart';
import 'ruler_overlay.dart';
import 'text_layer.dart';
import 'tool_controller.dart';
import 'tool_palette.dart';
import 'zoom_area.dart';
import 'metronome.dart';
import 'metronome_panel.dart';
import '../../core/library/score_meta.dart';
import '../library/settings_dialog.dart';

/// Ein Stück, das im Notenbetrachter angezeigt wird.
class ViewerItem {
  const ViewerItem(this.path, this.title, {this.bookmark, this.setlistId, this.setlistName});
  final String path;
  final String title;

  /// Aus dieser Setlist geöffnet: Notizen gehören dann zur Setlist (eigene
  /// Ebene, nur dort sichtbar), nicht zum Song in der Bibliothek.
  final String? setlistId;
  final String? setlistName;

  /// Nur den Bereich dieses Lesezeichens zeigen (z. B. ein Lied aus einem
  /// Sammelband in einer Setlist).
  final String? bookmark;
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
    this.addBookmarkToSetlist,
  });

  final List<ViewerItem> items;

  /// Lesezeichen als eigenes Stück in eine Setlist legen (von der Bibliothek).
  final Future<void> Function(BuildContext context, String path, Bookmark bookmark)? addBookmarkToSetlist;
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
  _Piece(this.item) : ink = InkController(pdfPath: item.path, scope: item.setlistId, scopeName: item.setlistName);

  final ViewerItem item;
  final InkController ink;
  PdfDocument? doc;
  PageImageCache? cache;
  String? error;
  late final Future<void> ready = _load();

  /// Reihenfolge und Zuschnitt der Seiten (das PDF bleibt unverändert).
  PageSetup setup = PageSetup.empty;

  /// Infos des Stücks (z. B. Tempo fürs Metronom).
  ScoreMeta meta = ScoreMeta();

  int? _int(String field) {
    final v = meta.fields[field]?.value;
    return v is num && v > 0 ? v.round() : null;
  }

  int? get tempo => _int(ScoreMeta.tempo);
  int? get beats => _int(ScoreMeta.beats);

  /// Angezeigte Seiten als PDF-Seitennummern.
  /// Angezeigte Seiten – bei einem Lesezeichen nur dessen Bereich.
  List<int> get _shown => shownPages(setup, cache?.pageCount ?? 0, ink.annotations, item.bookmark);

  /// Alle angezeigten Seiten des Stücks (ohne Lesezeichen-Bereich).
  List<int> get allShown => setup.pages(cache?.pageCount ?? 0);

  /// Anzahl angezeigter Seiten (null, solange das Stück lädt).
  int? get pageCount => cache == null ? (error != null ? 0 : null) : _shown.length;

  /// PDF-Seite zur angezeigten Seite [display] (1-basiert).
  int source(int display) {
    final s = _shown;
    if (s.isEmpty) return display;
    return s[(display - 1).clamp(0, s.length - 1)];
  }

  PageCrop crop(int display) => setup.cropOf(source(display));

  /// Position (0-basiert) der angezeigten Seite [display] in der ganzen
  /// Reihenfolge – bei einem Lesezeichen liegt sein Bereich mittendrin.
  int fullIndex(int display) {
    final shown = _shown;
    if (shown.isEmpty) return display - 1;
    return allShown.indexOf(shown.first) + (display - 1).clamp(0, shown.length - 1);
  }

  /// Seitenverhältnis der angezeigten Seite (nach Zuschnitt und Drehung).
  double aspect(int display) => crop(display).displayAspect(cache!.aspectRatio(source(display)));

  Future<void> _load() async {
    try {
      final d = await PdfDocument.openFile(item.path);
      await ink.load();
      final side = await const SidecarStore().load(item.path);
      setup = side.pages;
      meta = side.meta;
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

  /// Vergrösserung mit zwei Fingern (bzw. Strg + Mausrad).
  final _zoom = PageZoom();

  /// Metronom: Tempo aus den Infos des Stücks, jederzeit anpassbar.
  final _metronome = Metronome();
  bool _metronomeOpen = false;
  int? _metronomePiece;

  final _diagnostics = PenDiagnostics();
  bool _showDiagnostics = false;

  /// Nach einem Sprung: Ziel kurz aufblinken lassen, und von wo man kam.
  final _flash = ValueNotifier<JumpFlash?>(null);
  PageSlot? _returnTo;
  Timer? _returnTimer;

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
    final half = _half && _halfMode ? _flow.after(_left) : null;
    if (half != null) {
      return half.piece == _left.piece
          ? 'Seite ${_left.page} → ${half.page} von $_pageCount'
          : 'Seite ${_left.page} → ${widget.items[half.piece].title}';
    }
    final r = _right;
    if (r == null) return 'Seite ${_left.page} von $_pageCount';
    if (r.piece == _left.piece) return 'Seiten ${_left.page}–${r.page} von $_pageCount';
    return 'Seite ${_left.page} von $_pageCount · rechts: ${widget.items[r.piece].title}';
  }

  _Piece get _activePiece => _pieces[(_activeSlot ?? _left).piece] ?? _leftPiece!;

  /// PDF-Seite der zuletzt berührten Seite (dort liegen ihre Anmerkungen).
  int get _activePage {
    final slot = _activeSlot ?? _left;
    return (_pieces[slot.piece] ?? _leftPiece!).source(slot.page);
  }

  @override
  void initState() {
    super.initState();
    tools.setMode(ToolMode.read);
    tools.addListener(_onToolsChanged);
    _zoom.settled.addListener(_onRenderScale);
    _zoom.matrix.addListener(_onZoom);
    _ensureAround(_left.piece);
    _restartHideTimer();
  }

  void _onZoom() => tools.viewScale = _zoom.scale;

  /// Nach dem Zoomen: Seiten in der neuen Grösse scharf rendern.
  void _onRenderScale() {
    if (mounted) setState(() {});
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
      if (mounted) {
        setState(() {});
        if (i == _left.piece) _adoptTempo();
      }
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

  /// Seiten des zuletzt berührten Stücks anordnen und zuschneiden.
  Future<void> _editPages() async {
    final index = (_activeSlot ?? _left).piece;
    final piece = _pieces[index];
    final doc = piece?.doc;
    if (piece == null || doc == null) return;
    tools.clearSelection();
    final result = await showPageSetup(context, doc: doc, setup: piece.setup, title: piece.item.title);
    if (result == null || !mounted) return;
    await _applySetup(index, result);
  }

  /// Neue Seiten-Einrichtung eines Stücks zeigen und speichern.
  Future<void> _applySetup(int index, PageSetup result) async {
    final piece = _pieces[index];
    if (piece == null) return;
    setState(() {
      piece.setup = result;
      _activeSlot = null;
      final count = piece.pageCount ?? 1;
      if (_left.piece == index && _left.page > count) _left = PageSlot(index, count);
    });
    try {
      await const SidecarStore().save(piece.item.path, pages: result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
      }
    }
  }

  /// Ist die zuletzt berührte Seite eine leere Seite?
  bool get _onBlankPage {
    final slot = _activeSlot ?? _left;
    final piece = _pieces[slot.piece];
    return piece?.cache != null && PageSetup.isBlank(piece!.source(slot.page));
  }

  /// Nach der zuletzt berührten Seite eine leere Seite für Notizen einfügen
  /// (das PDF bleibt unverändert) und gleich hinblättern.
  Future<void> _insertBlank() async {
    final slot = _activeSlot ?? _left;
    final piece = _pieces[slot.piece];
    final cache = piece?.cache;
    if (piece == null || cache == null) return;
    tools.clearSelection();
    final before = piece.setup;
    final (next, _) = before.withBlankAt(piece.fullIndex(slot.page) + 1, cache.pageCount);
    await _applySetup(slot.piece, next);
    if (!mounted) return;
    _show(PageSlot(slot.piece, (slot.page + 1).clamp(1, piece.pageCount ?? 1)));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        persist: false,
        duration: const Duration(seconds: 6),
        content: const Text('Leere Seite eingefügt'),
        action: SnackBarAction(
          label: 'Rückgängig',
          // Den Zähler behalten: eine spätere leere Seite bekommt nie dieselbe Nummer.
          onPressed: () => _applySetup(slot.piece, before.withOrder(before.order, blanks: next.blanks)),
        ),
      ),
    );
  }

  /// Die zuletzt berührte leere Seite entfernen (mit Rückgängig).
  Future<void> _removeBlank() async {
    final slot = _activeSlot ?? _left;
    final piece = _pieces[slot.piece];
    final cache = piece?.cache;
    if (piece == null || cache == null || !PageSetup.isBlank(piece.source(slot.page))) return;
    if (piece.allShown.length <= 1) return;
    tools.clearSelection();
    final before = piece.setup;
    final list = [...piece.allShown]..removeAt(piece.fullIndex(slot.page));
    await _applySetup(slot.piece, before.withOrder(list));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        persist: false,
        duration: const Duration(seconds: 6),
        content: const Text('Leere Seite entfernt'),
        action: SnackBarAction(
          label: 'Rückgängig',
          onPressed: () => _applySetup(slot.piece, before.withOrder(before.order)),
        ),
      ),
    );
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

  /// Halber Seitenwechsel läuft: oben schon die nächste Seite, unten noch
  /// das Ende der aktuellen.
  bool _half = false;

  /// Halbe Seitenwechsel gerade möglich? (Nur bei einer Seite.)
  bool get _halfMode => tools.halfTurns && !_twoUp;

  void _show(PageSlot slot) {
    if (_half) setState(() => _half = false);
    if (slot == _left) return;
    _zoom.reset();
    // Eine Auswahl auf einer Seite, die man nicht mehr sieht, wäre gefährlich
    // (z. B. Entf-Taste) – also aufheben. Die Zwischenablage bleibt.
    tools.clearSelection();
    setState(() {
      _left = slot;
      _activeSlot = null;
    });
    _ensureAround(slot.piece);
    // Nächster Song in der Setlist: sein Tempo (läuft das Metronom, gleich hörbar).
    _adoptTempo();
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
    _zoom.settled.removeListener(_onRenderScale);
    _zoom.matrix.removeListener(_onZoom);
    _zoom.dispose();
    _metronome.dispose();
    tools.viewScale = 1;
    tools.setMode(ToolMode.read);
    if (_fullscreen) setAppFullscreen(false);
    for (final p in _pieces.values) {
      p.dispose();
    }
    _diagnostics.dispose();
    _returnTimer?.cancel();
    _flash.dispose();
    super.dispose();
  }

  /// Endlosband: Notenzeilen des aktuellen Stücks untereinander.
  void _reflow() {
    final piece = _activePiece;
    final doc = piece.doc;
    if (doc == null) return;
    showReflow(
      context,
      title: piece.item.title,
      piece: ExportPiece(doc: doc, annotations: piece.ink.annotations, setup: piece.setup, pages: piece._shown),
    );
  }

  /// Das aktuelle Stück als PDF (mit Anmerkungen) speichern oder drucken.
  void _export() {
    final piece = _activePiece;
    final doc = piece.doc;
    if (doc == null) return;
    showExportDialog(
      context,
      title: piece.item.title,
      load: () async => [
        ExportPiece(doc: doc, annotations: piece.ink.annotations, setup: piece.setup, pages: piece._shown),
      ],
    );
  }

  /// Lesezeichen des aktuellen Stücks.
  void _openBookmarks() {
    final piece = _leftPiece;
    if (piece == null || piece.cache == null) return;
    final index = _left.piece;
    // In einem Lesezeichen-Eintrag einer Setlist gelten die Seiten des
    // ganzen Stücks; sonst die angezeigten.
    final shown = piece.item.bookmark == null ? piece._shown : piece.allShown;
    final current = shown.indexOf(piece.source(_left.page)) + 1;
    final add = widget.addBookmarkToSetlist;
    showBookmarks(
      context,
      ink: piece.ink,
      shown: shown,
      current: current.clamp(1, shown.length),
      onOpen: (display) {
        final pdf = shown[display - 1];
        final here = piece._shown.indexOf(pdf);
        if (here >= 0) _show(PageSlot(index, here + 1));
      },
      onAddToSetlist: add == null ? null : (b) => add(context, piece.item.path, b),
    );
  }

  /// Springt zum Ziel einer Sprungmarke und lässt es kurz aufblinken.
  void _jump(int pieceIndex, JumpLink l) {
    _lastJump = DateTime.now();
    final piece = _pieces[pieceIndex];
    final count = piece?.pageCount ?? 0;
    if (piece == null || count == 0) return;
    int? display;
    for (var d = 1; d <= count; d++) {
      if (piece.source(d) == l.toPage) {
        display = d;
        break;
      }
    }
    if (display == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Die Zielseite ist ausgeblendet (Seiten anordnen).')));
      return;
    }
    final target = PageSlot(pieceIndex, display);
    final visible = target == _left || target == _right;
    if (!visible) {
      final from = _left;
      _show(target);
      setState(() => _returnTo = from);
      _returnTimer?.cancel();
      _returnTimer = Timer(const Duration(seconds: 8), () {
        if (mounted) setState(() => _returnTo = null);
      });
    }
    final f = JumpFlash(piece.ink, l.toPage, l.toX, l.toY);
    _flash.value = f;
    Timer(const Duration(milliseconds: 1800), () {
      if (identical(_flash.value, f)) _flash.value = null;
    });
  }

  void _jumpBack() {
    final r = _returnTo;
    _returnTimer?.cancel();
    setState(() => _returnTo = null);
    if (r != null) _show(r);
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
    if (_halfMode) {
      final next = _flow.after(_left);
      if (next == null) return;
      if (!_half) {
        setState(() => _half = true); // erst oben die nächste Seite
      } else {
        _show(next); // jetzt ganz
      }
      return;
    }
    final target = _flow.next(_left, twoUp: _twoUp);
    if (target != null) _show(target);
  }

  Future<void> _prev() async {
    if (_left.piece > 0) await _ensure(_left.piece - 1);
    if (!mounted) return;
    if (_halfMode) {
      if (_half) {
        setState(() => _half = false); // wieder die ganze aktuelle Seite
        return;
      }
      final before = _flow.before(_left);
      if (before == null) return;
      _show(before);
      setState(() => _half = true); // halb zwischen der vorigen und dieser
      return;
    }
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

  /// Strg + Plus/Minus: um die Mitte vergrössern bzw. verkleinern.
  void _zoomStep(double factor) {
    final box = context.findRenderObject() as RenderBox?;
    final size = box?.size ?? MediaQuery.sizeOf(context);
    _zoom.zoomBy(factor, size.center(Offset.zero));
  }

  /// Kommt ein anderes Stück dran, sein Tempo übernehmen (falls eingetragen).
  void _adoptTempo() {
    final p = _leftPiece;
    if (p == null || p.cache == null || _metronomePiece == _left.piece) return;
    _metronomePiece = _left.piece;
    _metronome.adopt(bpm: p.tempo, beats: p.beats);
  }

  void _toggleMetronome() {
    _adoptTempo();
    setState(() => _metronomeOpen = !_metronomeOpen);
  }

  /// Eingestelltes Tempo und Taktart in den Infos des Stücks speichern.
  Future<void> _rememberTempo() async {
    final p = _leftPiece;
    if (p == null) return;
    final meta = ScoreMeta(p.meta.fields)
      ..set(ScoreMeta.tempo, _metronome.bpm)
      ..set(ScoreMeta.beats, _metronome.beats);
    try {
      final saved = await const SidecarStore().save(p.item.path, meta: meta);
      p.meta = saved.meta;
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${_metronome.bpm} BPM bei „${p.item.title}“ gespeichert')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
      }
    }
  }

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
    } else if (ctrl &&
        (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.add || key == LogicalKeyboardKey.numpadAdd)) {
      _zoomStep(1.25);
    } else if (ctrl && (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract)) {
      _zoomStep(0.8);
    } else if (ctrl && (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0)) {
      _zoom.reset();
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
    } else if (down && key == LogicalKeyboardKey.keyJ) {
      tools.setMode(ToolMode.link);
    } else if (down && !ctrl && key == LogicalKeyboardKey.keyA) {
      tools.setMode(ToolMode.lasso);
    } else if (down && key == LogicalKeyboardKey.keyM) {
      _adoptTempo();
      _metronome.toggle();
    } else if (down && key == LogicalKeyboardKey.keyL) {
      tools.toggleRuler();
    } else if (down && _digits.contains(key)) {
      tools.applyFavoriteIndex(_digits.indexOf(key));
    } else if (key == LogicalKeyboardKey.escape) {
      if (tools.selection.value != null) {
        tools.clearSelection();
      } else if (tools.editing) {
        tools.finishEditing();
      } else if (_zoom.isZoomed) {
        _zoom.reset();
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
            // Vergrössert: Anzeige und Knopf zurück auf die ganze Seite.
            Positioned(
              left: 0,
              right: 0,
              bottom: showBars && _pageCount > 1 ? 76 : 16,
              child: Center(
                child: ValueListenableBuilder<Matrix4>(
                  valueListenable: _zoom.matrix,
                  builder: (context, _, _) => !_zoom.isZoomed
                      ? const SizedBox.shrink()
                      : ExcludeFocus(
                          child: ActionChip(
                            avatar: const Icon(Icons.fit_screen_outlined, size: 18),
                            label: Text('${(_zoom.scale * 100).round()} %'),
                            tooltip: 'Ganze Seite zeigen (Esc)',
                            onPressed: _zoom.reset,
                          ),
                        ),
                ),
              ),
            ),
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
            // Nach einem Sprung: zurück, woher man kam (ein paar Sekunden lang)
            if (_returnTo != null)
              Positioned(
                left: 16,
                bottom: 24,
                child: ExcludeFocus(
                  child: FilledButton.tonalIcon(
                    onPressed: _jumpBack,
                    icon: const Icon(Icons.undo),
                    label: const Text('Zurück'),
                  ),
                ),
              ),
            if (_metronomeOpen)
              Positioned(
                right: 12,
                top: (showBars ? 64 : 12) + MediaQuery.paddingOf(context).top,
                child: ExcludeFocus(
                  child: RepaintBoundary(
                    child: MetronomePanel(
                      metronome: _metronome,
                      onClose: () => setState(() => _metronomeOpen = false),
                      onRemember: _leftPiece?.cache == null ? null : _rememberTempo,
                      songTempo: _leftPiece?.tempo,
                      songTitle: _leftPiece?.item.title,
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
        child: SafeArea(
          child: ZoomArea(
            zoom: _zoom,
            tools: tools,
            onTap: _cleanTap,
            child: LayoutBuilder(builder: (context, box) => _buildPages(box)),
          ),
        ),
      ),
    );
  }

  /// Linkes Drittel: zurück. Rechtes Drittel: weiter. Mitte: Leiste ein/aus.
  void _onTap(TapUpDetails d) {
    if (d.kind == PointerDeviceKind.invertedStylus) return;
    if (tools.rulerRecentlyUsed) return; // Finger war am Lineal
    if (_zoom.recentlyMoved) return; // Finger hat gezoomt oder verschoben
    _tapAt(d.globalPosition);
  }

  DateTime _lastTap = DateTime(2000);
  DateTime _lastJump = DateTime(2000);

  /// Rückfall: Ein sauberes Antippen (ein Finger bzw. Stift, kaum bewegt), das
  /// die übliche Erkennung nicht erreicht hat – z. B. im Zoom. Kurz warten,
  /// ob es schon behandelt wurde (oder eine Sprungmarke angetippt wurde).
  void _cleanTap(Offset global, PointerDeviceKind kind) {
    if (tools.mode != ToolMode.read) return;
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (!mounted || tools.mode != ToolMode.read || tools.rulerRecentlyUsed) return;
      final now = DateTime.now();
      if (now.difference(_lastTap) < const Duration(milliseconds: 400)) return;
      if (now.difference(_lastJump) < const Duration(milliseconds: 400)) return;
      _tapAt(global);
    });
  }

  void _tapAt(Offset global) {
    _lastTap = DateTime.now();
    final width = MediaQuery.sizeOf(context).width;
    final x = global.dx / width;
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
    // Vergrössert verschiebt der Finger die Seite, statt umzublättern.
    if (_zoom.isZoomed || _zoom.recentlyMoved) return;
    final v = d.primaryVelocity ?? 0;
    if (v < -300) _next();
    if (v > 300) _prev();
  }

  /// Eine oder zwei Seiten, so gross wie möglich.
  Widget _buildPages(BoxConstraints box) {
    const margin = 6.0, gap = 8.0;
    final availW = box.maxWidth - 2 * margin;
    final availH = box.maxHeight - 2 * margin;
    final halfNext = _half && _halfMode ? _flow.after(_left) : null;
    final slots = [_left, ?_right, ?halfNext];
    double aspectOf(PageSlot s) {
      final p = _pieces[s.piece];
      if (p?.cache != null) return p!.aspect(s.page);
      final l = _leftPiece;
      return l?.cache == null ? 0.707 : l!.aspect(_left.page);
    }

    if (halfNext != null) return _buildHalf(halfNext, availW, availH, aspectOf);
    final aspects = [for (final s in slots) aspectOf(s)];
    final totalAspect = aspects.reduce((a, b) => a + b);
    final gaps = gap * (slots.length - 1);
    final h = ((availW - gaps) / availH > totalAspect ? availH : (availW - gaps) / totalAspect);

    // Sichtbare Seiten nicht aus dem Zwischenspeicher verdrängen; die
    // nächsten Seiten schon vorbereiten, damit das Umblättern sofort geht.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final visibleByPiece = <int, Set<int>>{};
    for (final s in slots) {
      final p = _pieces[s.piece];
      if (p != null) (visibleByPiece[s.piece] ??= {}).add(p.source(s.page));
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
      final p = _pieces[s.piece];
      final c = p?.cache;
      if (p == null || c == null) continue;
      final full = CroppedPage.fullSizeFor(p.crop(s.page), Size(h * p.aspect(s.page), h));
      c.preload([p.source(s.page)], ((full.width * dpr / 128).ceil() * 128).clamp(128, 4096));
    }

    // Vergrössert: nur sichtbare Seiten scharf rendern (Speicher und Zeit).
    final view = _zoom.visibleContent;
    final rowW = aspects.fold<double>(0, (a, b) => a + b * h) + gaps;
    var x = (box.maxWidth - rowW) / 2;
    final top = (box.maxHeight - h) / 2;
    final visible = <bool>[];
    for (final a in aspects) {
      visible.add(!_zoom.isZoomed || Rect.fromLTWH(x, top, a * h, h).overlaps(view));
      x += a * h + gap;
    }
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, s) in slots.indexed) ...[
            if (i > 0) const SizedBox(width: gap),
            _buildPage(s, h * aspects[i], h, dpr, sharpen: visible[i]),
          ],
        ],
      ),
    );
  }

  /// Halber Seitenwechsel: oben die obere Hälfte der nächsten Seite, unten
  /// die untere Hälfte der aktuellen – getrennt durch eine feine Linie.
  Widget _buildHalf(PageSlot next, double availW, double availH, double Function(PageSlot) aspectOf) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    Size fit(PageSlot s) {
      final a = aspectOf(s);
      final h = availW / availH > a ? availH : availW / a;
      return Size(h * a, h);
    }

    final cur = fit(_left), nxt = fit(next);
    for (final s in [_left, next]) {
      final p = _pieces[s.piece];
      p?.cache?.setVisiblePages({
        for (final x in [_left, next])
          if (x.piece == s.piece) p.source(x.page),
      });
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: 0.5,
              child: _buildPage(next, nxt.width, nxt.height, dpr),
            ),
          ),
          Container(height: 3, width: math.max(cur.width, nxt.width), color: VoltiColors.seafoam),
          ClipRect(
            child: Align(
              alignment: Alignment.bottomCenter,
              heightFactor: 0.5,
              child: _buildPage(_left, cur.width, cur.height, dpr),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(PageSlot slot, double w, double h, double dpr, {bool sharpen = true}) {
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
    final src = piece.source(slot.page);
    final crop = piece.crop(slot.page);
    final full = CroppedPage.fullSizeFor(crop, Size(w, h));
    // In 128-Pixel-Schritten rendern, damit nicht jede kleine
    // Fensteränderung ein neues Rendern auslöst. Bei einem Ausschnitt wird
    // die ganze Seite entsprechend grösser gerendert (bleibt scharf).
    // Vergrössert: Seite und Anmerkungen in höherer Auflösung (scharf).
    // Höchstens 4096 Punkte auf der längeren Seite (Speicher).
    final zoomed = sharpen ? _zoom.renderScale.value : 1.0;
    final sharp = zoomed <= 1 ? 1.0 : math.max(1.0, math.min(zoomed, 4096 / (math.max(full.width, full.height) * dpr)));
    final pixelWidth = ((full.width * dpr * sharp / 128).ceil() * 128).clamp(128, 4096);
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
        // Weisse Seite ohne Schatten (ein weicher Schatten kostet beim Malen viel Zeit).
        child: ColoredBox(
          color: Colors.white,
          // Zuschnitt, Drehung und Geraderichten: Die Ebenen darin arbeiten
          // immer mit der ganzen PDF-Seite [src].
          child: CroppedPage(
            crop: crop,
            size: Size(w, h),
            page: (_) => _sharper(
              sharp,
              Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.white),
                  // Die Stift-Ebene malt auch die Notenseite: Seite, Leuchtstift und
                  // alle Ebenen werden dort zu einem einzigen Bild (schneller).
                  ListenableBuilder(
                    listenable: cache,
                    builder: (context, _) => InkLayer(
                      key: ValueKey('ink/$key'),
                      page: src,
                      controller: piece.ink,
                      tools: tools,
                      pageImage: cache.imageFor(src, pixelWidth),
                    ),
                  ),
                  RepaintBoundary(
                    child: TextNotesLayer(
                      key: ValueKey('text/$key'),
                      page: src,
                      controller: piece.ink,
                      tools: tools,
                      onEditingChanged: (v) => setState(() => _editingText = v),
                    ),
                  ),
                  // Sprungmarken (blaue Punkte) und das Aufblinken am Ziel
                  RepaintBoundary(
                    child: LinksLayer(
                      key: ValueKey('links/$key'),
                      page: src,
                      controller: piece.ink,
                      tools: tools,
                      flash: _flash,
                      onJump: (l) => _jump(slot.piece, l),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Bilder in [factor]-facher Auflösung (für den Zoom): Die Ebenen richten
  /// sich nach dem Pixelverhältnis des Bildschirms.
  /// Immer mit demselben Aufbau (auch bei 1), damit beim Zoomen nichts neu
  /// entsteht – z. B. bleibt eine gerade getippte Text-Notiz offen.
  static Widget _sharper(double factor, Widget child) {
    return Builder(
      builder: (context) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(devicePixelRatio: mq.devicePixelRatio * factor),
          child: child,
        );
      },
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
                  ListenableBuilder(
                    listenable: state._metronome,
                    builder: (context, _) => IconButton(
                      tooltip: 'Metronom (M)',
                      isSelected: state._metronomeOpen || state._metronome.running,
                      icon: MetronomeIcon(
                        color: state._metronome.running ? Theme.of(context).colorScheme.primary : null,
                      ),
                      onPressed: state._toggleMetronome,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Als PDF teilen oder drucken',
                    icon: const Icon(Icons.ios_share),
                    onPressed: state._export,
                  ),
                  IconButton(
                    tooltip: 'Lesezeichen',
                    icon: const Icon(Icons.bookmarks_outlined),
                    onPressed: state._openBookmarks,
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
                      PopupMenuItem(
                        value: () => showSettingsDialog(context),
                        child: const ListTile(
                          leading: Icon(Icons.settings_outlined),
                          title: Text('Einstellungen …'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: state._reflow,
                        child: const ListTile(
                          leading: Icon(Icons.view_day_outlined),
                          title: Text('Endlosband (Notenzeilen untereinander)'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: state._insertBlank,
                        child: const ListTile(
                          leading: Icon(Icons.note_add_outlined),
                          title: Text('Leere Seite einfügen (für Notizen)'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      if (state._onBlankPage)
                        PopupMenuItem(
                          value: state._removeBlank,
                          child: const ListTile(
                            leading: Icon(Icons.delete_outline),
                            title: Text('Diese leere Seite entfernen'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      PopupMenuItem(
                        value: state._editPages,
                        child: const ListTile(
                          leading: Icon(Icons.auto_stories_outlined),
                          title: Text('Seiten anordnen und zuschneiden …'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: tools.openLayers,
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
