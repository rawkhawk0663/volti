import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/app_settings.dart';
import '../../core/ink/stroke.dart';
import '../../core/ink/tool_settings.dart';

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

  static const eraserSizes = [8.0, 14.0, 26.0];

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

  void finishEditing() => setMode(ToolMode.read);

  void setMode(ToolMode m) {
    if (_mode == m) return;
    _mode = m;
    if (m != ToolMode.read && m != ToolMode.none) _lastTool = m;
    notifyListeners();
  }

  /// Werkzeug in der Palette angetippt: wählen – oder, wenn es schon aktiv
  /// ist, abwählen (das Einstellungsfenster verschwindet dann).
  void tapTool(ToolMode m) => setMode(_mode == m ? ToolMode.none : m);

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
    _s.eraserRadius = r;
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

  @override
  void dispose() {
    _saveTimer?.cancel();
    isDrawing.dispose();
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
