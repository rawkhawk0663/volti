import 'package:flutter/widgets.dart';

import '../../core/app_settings.dart';
import '../../core/ink/drawing_preset.dart';
import '../../core/ink/stroke.dart';

/// Was der Stift gerade tut.
enum ToolMode {
  /// Spielansicht: Antippen blättert. Mit dem Stift ziehen zeichnet trotzdem
  /// (wenn "sofort zeichnen" an ist).
  read,

  /// Zeichnen mit der gewählten Stift-Vorlage.
  draw,
  eraser,
  text,
}

/// Werkzeuge und Stift-Vorlagen – gelten in allen Stücken.
///
/// Die Vorlagen liegen in der Bibliothek und werden synchronisiert; die
/// Bedien-Vorlieben (Vollbild, Palettenseite …) gelten nur für dieses Gerät.
class ToolController extends ChangeNotifier {
  ToolController({required this.settings, required this.store});

  final AppSettings settings;
  final PresetStore store;

  /// Nach jeder Änderung an den Vorlagen (für den Sync).
  VoidCallback? onPresetsChanged;

  List<DrawingPreset> _presets = List.of(DrawingPreset.defaults);
  List<DrawingPreset> get presets => List.unmodifiable(_presets);

  String _selectedId = DrawingPreset.defaults.first.id;

  ToolMode _mode = ToolMode.read;
  ToolMode get mode => _mode;

  /// Wird gerade gezeichnet? Dann wird die Palette fast durchsichtig.
  final isDrawing = ValueNotifier<bool>(false);

  static const eraserSizes = [8.0, 14.0, 26.0];
  double eraserRadius = eraserSizes[1];

  static const textSizes = [0.016, 0.022, 0.032];
  double textSize = textSizes[1];

  Future<void> load() async {
    _presets = await store.load();
    if (!_presets.any((p) => p.id == _selectedId)) _selectedId = _presets.first.id;
    notifyListeners();
  }

  DrawingPreset get current => _presets.firstWhere((p) => p.id == _selectedId, orElse: () => _presets.first);

  /// Farbe für Text-Notizen: die des aktuellen Stifts (Textmarker → Schwarz).
  int get textColor =>
      current.tool == InkTool.pen && current.color != 0xFFFFFFFF ? current.color | 0xFF000000 : 0xFF1B1B1B;

  // -------------------------------------------------------- Geräte-Vorlieben
  bool get fullscreen => settings.flag('viewerFullscreen', orElse: true);
  bool get instantPen => settings.flag('instantPen', orElse: true);
  bool get paletteLeft => settings.flag('paletteLeft', orElse: true);

  Future<void> setFullscreen(bool v) => _setFlag('viewerFullscreen', v);
  Future<void> setInstantPen(bool v) => _setFlag('instantPen', v);
  Future<void> togglePaletteSide() => _setFlag('paletteLeft', !paletteLeft);

  Future<void> _setFlag(String name, bool v) async {
    await settings.setFlag(name, v);
    notifyListeners();
  }

  // ------------------------------------------------------------- Werkzeuge
  void setMode(ToolMode m) {
    if (_mode == m) return;
    _mode = m;
    notifyListeners();
  }

  void select(DrawingPreset p) {
    _selectedId = p.id;
    _mode = ToolMode.draw;
    notifyListeners();
  }

  /// Taste "H": erster Textmarker; Taste "P": erster Stift.
  void selectFirst(InkTool tool) {
    final p = _presets.where((p) => p.tool == tool).firstOrNull;
    if (p != null) select(p);
  }

  void selectIndex(int i) {
    if (i >= 0 && i < _presets.length) select(_presets[i]);
  }

  void setEraserRadius(double r) {
    eraserRadius = r;
    _mode = ToolMode.eraser;
    notifyListeners();
  }

  void setTextSize(double s) {
    textSize = s;
    _mode = ToolMode.text;
    notifyListeners();
  }

  // --------------------------------------------------------- Vorlagen pflegen
  DrawingPreset addPreset() {
    final p = current.copyWith(id: PresetStore.newId());
    _presets.insert(_presets.indexOf(current) + 1, p);
    select(p);
    _persist();
    return p;
  }

  void updatePreset(DrawingPreset p) {
    final i = _presets.indexWhere((x) => x.id == p.id);
    if (i < 0) return;
    _presets[i] = p;
    notifyListeners();
    _persist();
  }

  void deletePreset(DrawingPreset p) {
    if (_presets.length <= 1) return;
    final i = _presets.indexWhere((x) => x.id == p.id);
    if (i < 0) return;
    _presets.removeAt(i);
    if (_selectedId == p.id) _selectedId = _presets[(i - 1).clamp(0, _presets.length - 1)].id;
    notifyListeners();
    _persist();
  }

  void movePreset(int from, int to) {
    if (from == to || from < 0 || from >= _presets.length) return;
    final p = _presets.removeAt(from);
    _presets.insert(to.clamp(0, _presets.length), p);
    notifyListeners();
    _persist();
  }

  // Speichervorgänge nacheinander ausführen, nie gleichzeitig – sonst
  // kämen sich schnelle Änderungen (z. B. neu + sofort bearbeiten) in die Quere.
  Future<void> _saving = Future.value();

  Future<void> _persist() {
    _saving = _saving.then((_) async {
      try {
        await store.save(List.of(_presets));
        onPresetsChanged?.call();
      } catch (_) {
        // Beim nächsten Ändern wird erneut gespeichert.
      }
    });
    return _saving;
  }

  /// Wartet, bis alle Änderungen gespeichert sind.
  Future<void> flush() => _saving;

  @override
  void dispose() {
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
