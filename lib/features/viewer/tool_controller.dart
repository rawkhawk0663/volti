import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/app_settings.dart';
import '../../core/ink/selection.dart';
import '../../core/ink/stroke.dart';
import '../../core/ink/tool_settings.dart';
import 'ink_controller.dart';

/// Was gerade aktiv ist.
enum ToolMode {
  /// Spielansicht (nicht bearbeiten). Mit dem Stift ziehen zeichnet trotzdem,
  /// wenn "sofort zeichnen" an ist – mit den Stift-Einstellungen.
  read,

  /// Bearbeiten, aber kein Werkzeug gewählt.
  none,
  pen,
  highlighter,
  eraser,
  text,
  stamp,
  shape,

  /// Auswählen (Lasso): einkreisen, dann verschieben, kopieren, umfärben …
  lasso,
}

/// Ausgewählte Elemente auf einer Seite eines Stücks.
class InkSelection {
  const InkSelection(this.controller, this.page, this.ids);
  final InkController controller;
  final int page;
  final SelectionIds ids;

  bool isOn(InkController c, int p) => identical(controller, c) && page == p;

  /// Nur, was es noch gibt (z. B. nach "Rückgängig").
  SelectionIds get live => ids.liveIn(controller.annotations);
}

/// Wie viele Seiten nebeneinander gezeigt werden.
enum PageLayout {
  /// Querformat → zwei Seiten, Hochformat → eine Seite.
  auto,
  single,
  double;

  static PageLayout fromName(String? n) => PageLayout.values.firstWhere((l) => l.name == n, orElse: () => auto);
}

/// Werkzeuge, ihre Einstellungen und Favoriten – gelten in allen Stücken.
///
/// Einstellungen und Favoriten liegen in der Bibliothek und werden
/// synchronisiert. Bedien-Vorlieben (Vollbild, Palettenseite …) gelten nur
/// für dieses Gerät.
class ToolController extends ChangeNotifier {
  ToolController({required this.settings, required this.store});

  final AppSettings settings;
  final ToolStore store;

  /// Nach jeder Änderung an Einstellungen/Favoriten (für den Sync).
  VoidCallback? onSettingsChanged;

  ToolSettings _s = ToolSettings.defaults();
  ToolSettings get values => _s;

  ToolMode _mode = ToolMode.read;
  ToolMode get mode => _mode;
  bool get editing => _mode != ToolMode.read;

  /// Zuletzt gewähltes Werkzeug (beim nächsten "Bearbeiten" wieder aktiv).
  ToolMode _lastTool = ToolMode.pen;

  /// Wird gerade gezeichnet? Dann werden Palette und Einstellungsfenster
  /// fast durchsichtig.
  final isDrawing = ValueNotifier<bool>(false);

  /// Position des Einstellungsfensters (null = neben der Palette).
  /// Bleibt erhalten, wenn man das Werkzeug wechselt.
  Offset? popoverOffset;

  /// Grösse des teilweisen Radierers (Radius in Bildschirmpunkten).
  static const eraserMin = 2.0;
  static const eraserMax = 30.0;

  Future<void> load() async {
    _s = await store.load();
    notifyListeners();
  }

  // ------------------------------------------------------- aktuelle Werte
  DrawingPreset get pen => _s.pen;
  DrawingPreset get highlighter => _s.highlighter;
  TextStyleSetting get textStyle => _s.text;
  double get eraserRadius => _s.eraserRadius;
  bool get eraserPartial => _s.eraserPartial;

  /// Womit ein Strich gezeichnet wird (Textmarker oder Stift).
  DrawingPreset get strokeStyle => _mode == ToolMode.highlighter ? _s.highlighter : _s.pen;

  // -------------------------------------------------------- Geräte-Vorlieben
  bool get instantPen => settings.flag('instantPen', orElse: true);
  PageLayout get pageLayout => PageLayout.fromName(settings.text('pageLayout'));

  Future<void> setPageLayout(PageLayout l) async {
    await settings.setText('pageLayout', l.name);
    notifyListeners();
  }

  bool get paletteLeft => settings.flag('paletteLeft', orElse: true);

  Future<void> setInstantPen(bool v) => _setFlag('instantPen', v);
  Future<void> togglePaletteSide() async {
    popoverOffset = null; // Fenster wieder neben die Palette
    await _setFlag('paletteLeft', !paletteLeft);
  }

  Future<void> _setFlag(String name, bool v) async {
    await settings.setFlag(name, v);
    notifyListeners();
  }

  // ------------------------------------------------------------- Werkzeuge
  /// "Bearbeiten": mit dem zuletzt benutzten Werkzeug beginnen.
  void startEditing() => setMode(_lastTool);

  /// Zeigt das Werkzeug-Fenster die Ebenen? (Am selben Ort wie die
  /// Werkzeug-Einstellungen; das gewählte Werkzeug bleibt aktiv.)
  bool layersOpen = false;

  void toggleLayers() {
    layersOpen = !layersOpen;
    notifyListeners();
  }

  void openLayers() {
    if (!editing) setMode(_lastTool);
    layersOpen = true;
    notifyListeners();
  }

  void finishEditing() => setMode(ToolMode.read);

  void setMode(ToolMode m) {
    final closed = layersOpen;
    layersOpen = false; // ein Werkzeug gewählt → wieder seine Einstellungen zeigen
    if (_mode == m) {
      if (closed) notifyListeners();
      return;
    }
    if (m != ToolMode.lasso) clearSelection();
    _mode = m;
    if (m != ToolMode.read && m != ToolMode.none) _lastTool = m;
    notifyListeners();
  }

  /// Werkzeug in der Palette angetippt: wählen – oder, wenn es schon aktiv
  /// ist, abwählen (das Einstellungsfenster verschwindet dann).
  void tapTool(ToolMode m) {
    // Sind gerade die Ebenen offen, zeigt das Antippen wieder das Werkzeug.
    if (layersOpen) return setMode(m);
    setMode(_mode == m ? ToolMode.none : m);
  }

  // ------------------------------------------------------ Einstellungen
  void setPen(DrawingPreset p) {
    _s.pen = p;
    _changed();
  }

  void setHighlighter(DrawingPreset p) {
    _s.highlighter = p;
    _changed();
  }

  void setTextStyle(TextStyleSetting t, {bool save = true}) {
    _s.text = t;
    save ? _changed() : notifyListeners();
  }

  void setEraserRadius(double r) {
    _s.eraserRadius = r.clamp(eraserMin, eraserMax);
    _changed();
  }

  void setEraserPartial(bool partial) {
    _s.eraserPartial = partial;
    _changed();
  }

  /// Favoriten des Stifts bzw. Textmarkers.
  List<DrawingPreset> favoritesFor(InkTool t) =>
      List.unmodifiable(t == InkTool.highlighter ? _s.highlighterFavorites : _s.penFavorites);

  List<TextStyleSetting> get textFavorites => List.unmodifiable(_s.textFavorites);

  void applyFavorite(DrawingPreset f) => f.tool == InkTool.highlighter ? setHighlighter(f) : setPen(f);

  /// Speichert die aktuelle Einstellung als Favorit (falls noch nicht vorhanden).
  void addCurrentAsFavorite(InkTool t) {
    final list = t == InkTool.highlighter ? _s.highlighterFavorites : _s.penFavorites;
    final current = t == InkTool.highlighter ? _s.highlighter : _s.pen;
    if (list.any((f) => f.sameLook(current))) return;
    list.add(current.copyWith(id: ToolStore.newId()));
    _changed();
  }

  void removeFavorite(DrawingPreset f) {
    (f.tool == InkTool.highlighter ? _s.highlighterFavorites : _s.penFavorites).removeWhere((x) => x.id == f.id);
    _changed();
  }

  void addCurrentTextFavorite() {
    if (_s.textFavorites.any((f) => f.sameLook(_s.text))) return;
    _s.textFavorites.add(_s.text.copyWith(id: ToolStore.newId()));
    _changed();
  }

  void removeTextFavorite(TextStyleSetting f) {
    _s.textFavorites.removeWhere((x) => x.id == f.id);
    _changed();
  }

  /// Taste 1–9: Favorit des aktiven Werkzeugs (in der Spielansicht: Stift).
  void applyFavoriteIndex(int i) {
    switch (_mode) {
      case ToolMode.text:
        if (i < _s.textFavorites.length) setTextStyle(_s.textFavorites[i]);
      case ToolMode.highlighter:
        if (i < _s.highlighterFavorites.length) setHighlighter(_s.highlighterFavorites[i]);
      default:
        if (i < _s.penFavorites.length) {
          setPen(_s.penFavorites[i]);
          if (_mode != ToolMode.read) setMode(ToolMode.pen);
        }
    }
  }

  // ---------------------------------------------------------- Stempel/Formen
  StampSetting get stamp => _s.stamp;
  List<int> get recentStamps => List.unmodifiable(_s.recentStamps);
  DrawingPreset get shape => _s.shape;
  ShapeKind get shapeKind => _s.shapeKind;

  void setStamp(StampSetting st) {
    _s.stamp = st;
    _changed();
  }

  /// Merkt sich einen benutzten Stempel (für "Zuletzt benutzt").
  void rememberStamp(int glyph) {
    _s.recentStamps
      ..remove(glyph)
      ..insert(0, glyph);
    if (_s.recentStamps.length > 10) _s.recentStamps.removeLast();
    _changed();
  }

  void setShape(DrawingPreset p) {
    _s.shape = p;
    _changed();
  }

  void setShapeKind(ShapeKind k) {
    _s.shapeKind = k;
    _changed();
  }

  // ---------------------------------------------------------------- Lineal
  /// Lineal sichtbar? (Gilt nur für diese Sitzung.)
  bool rulerVisible = false;

  /// Mitte (Bildschirm-Koordinaten; null = Bildschirmmitte) und Drehwinkel.
  Offset? rulerCenter;
  double rulerAngle = 0;

  /// Länge und Breite des Lineals in Bildpunkten.
  static const rulerLength = 560.0, rulerThickness = 64.0;

  final rulerChanged = ValueNotifier<int>(0);

  void toggleRuler() {
    rulerVisible = !rulerVisible;
    notifyListeners();
    rulerChanged.value++;
  }

  /// Zeiger (Finger/Maus), die gerade das Lineal bewegen. Die Stift-Ebene
  /// zeichnet mit ihnen nicht, und ein Antippen blättert nicht um.
  final Set<int> rulerPointers = {};
  DateTime _rulerTouched = DateTime(2000);

  void grabRuler(int pointer) {
    rulerPointers.add(pointer);
    _rulerTouched = DateTime.now();
  }

  void releaseRuler(int pointer) {
    rulerPointers.remove(pointer);
    _rulerTouched = DateTime.now();
  }

  /// Wurde das Lineal gerade eben bewegt? (Dann ist ein Antippen kein Umblättern.)
  bool get rulerRecentlyUsed =>
      rulerPointers.isNotEmpty || DateTime.now().difference(_rulerTouched) < const Duration(milliseconds: 400);

  void moveRuler(Offset center, double angle) {
    rulerCenter = center;
    rulerAngle = angle;
    rulerChanged.value++;
  }

  // ------------------------------------------------------------ Speichern
  Timer? _saveTimer;
  Future<void> _saving = Future.value();

  void _changed() {
    notifyListeners();
    // Kurz warten: Beim Ziehen eines Reglers nicht bei jeder Bewegung speichern.
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _persist);
  }

  // Speichervorgänge nacheinander ausführen, nie gleichzeitig.
  Future<void> _persist() {
    _saving = _saving.then((_) async {
      try {
        await store.save(_s);
        onSettingsChanged?.call();
      } catch (_) {
        // Beim nächsten Ändern wird erneut gespeichert.
      }
    });
    return _saving;
  }

  /// Speichert sofort alle offenen Änderungen.
  Future<void> flush() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _persist();
    }
    return _saving;
  }

  // ------------------------------------------------------ Auswahl (Lasso)

  /// Aktuelle Auswahl (höchstens eine, app-weit).
  final selection = ValueNotifier<InkSelection?>(null);

  /// Zwischenablage für Anmerkungen – gilt app-weit, auch für andere Stücke.
  InkClip? get clipboard => _clipboard;
  InkClip? _clipboard;
  InkSelection? _clipSource;
  int _pasteCount = 0;

  void select(InkSelection? s) => selection.value = (s == null || s.ids.isEmpty) ? null : s;

  void clearSelection() {
    if (selection.value != null) selection.value = null;
  }

  void copySelection() {
    final s = selection.value;
    if (s == null) return;
    final clip = s.controller.copySelection(s.live);
    if (clip.isEmpty) return;
    _clipboard = clip;
    _clipSource = s;
    _pasteCount = 0;
    notifyListeners();
  }

  void cutSelection() {
    copySelection();
    deleteSelection();
  }

  void deleteSelection() {
    final s = selection.value;
    if (s == null) return;
    s.controller.deleteSelection(s.live);
    clearSelection();
  }

  /// Kopie gleich daneben (leicht versetzt), die dann ausgewählt ist.
  void duplicateSelection() {
    final s = selection.value;
    if (s == null) return;
    final clip = s.controller.copySelection(s.live);
    if (clip.isEmpty) return;
    final ids = s.controller.paste(clip, s.page, offset: const Offset(0.02, 0.02));
    select(InkSelection(s.controller, s.page, ids));
  }

  /// Fügt die Zwischenablage auf [page] von [target] ein. Auf derselben
  /// Seite wie das Original leicht versetzt, sonst an derselben Stelle.
  void pasteInto(InkController target, int page) {
    final clip = _clipboard;
    if (clip == null || clip.isEmpty) return;
    final src = _clipSource;
    final samePlace = src != null && src.isOn(target, page);
    final step = samePlace ? ++_pasteCount * 0.02 : 0.0;
    final ids = target.paste(clip, page, offset: Offset(step, step));
    if (_mode != ToolMode.lasso) setMode(ToolMode.lasso);
    select(InkSelection(target, page, ids));
  }

  void recolorSelection(int color) {
    final s = selection.value;
    if (s == null) return;
    s.controller.recolorSelection(s.live, color);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    selection.dispose();
    isDrawing.dispose();
    rulerChanged.dispose();
    super.dispose();
  }
}

/// Stellt den [ToolController] allen Bildschirmen zur Verfügung.
class ToolScope extends InheritedNotifier<ToolController> {
  const ToolScope({super.key, required ToolController tools, required super.child}) : super(notifier: tools);

  static ToolController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ToolScope>()!.notifier!;

  /// Ohne Abhängigkeit (z. B. in Callbacks).
  static ToolController read(BuildContext context) => context.getInheritedWidgetOfExactType<ToolScope>()!.notifier!;
}
