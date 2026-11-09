import 'annotation_layer.dart';
import 'stamp.dart';
import 'stroke.dart';
import 'text_note.dart';

/// Alle Anmerkungen zu einem Notenstück (einem PDF).
///
/// Das ist die Einheit, die als Datei neben dem PDF gespeichert und später
/// zwischen Geräten synchronisiert wird.
class ScoreAnnotations {
  ScoreAnnotations([
    Iterable<Stroke> strokes = const [],
    Iterable<TextNote> texts = const [],
    Iterable<Stamp> stamps = const [],
    Iterable<AnnotationLayer> layers = const [],
  ]) {
    for (final l in layers) {
      _layers[l.id] = l;
    }
    for (final st in stamps) {
      _stamps[st.id] = st;
    }
    for (final s in strokes) {
      _strokes[s.id] = s;
    }
    for (final t in texts) {
      _texts[t.id] = t;
    }
  }

  static const int formatVersion = 1;

  final Map<String, Stroke> _strokes = {};
  final Map<String, TextNote> _texts = {};
  final Map<String, Stamp> _stamps = {};
  final Map<String, AnnotationLayer> _layers = {};

  // ---------------------------------------------------------------- Ebenen

  /// Alle Ebenen inkl. gelöschter (für Speichern/Sync).
  Iterable<AnnotationLayer> get allLayers => _layers.values;

  /// Ebenen von unten nach oben. Die Grund-Ebene ist immer dabei.
  List<AnnotationLayer> get layers {
    final list = [
      for (final l in _layers.values)
        if (!l.deleted || l.isDefault) l,
    ];
    if (!_layers.containsKey(kDefaultLayer)) list.add(AnnotationLayer.standard());
    list.sort((a, b) {
      final c = a.order.compareTo(b.order);
      return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  AnnotationLayer? layer(String id) => _layers[id] ?? (id == kDefaultLayer ? AnnotationLayer.standard() : null);

  void putLayer(AnnotationLayer l) => _layers[l.id] = l;

  /// Auf welcher Ebene ein Element liegt. Fehlt die Ebene (gelöscht oder von
  /// einer neueren Version), gilt die Grund-Ebene.
  String resolveLayer(String? id) {
    if (id == null || id == kDefaultLayer) return kDefaultLayer;
    final l = _layers[id];
    return l == null || l.deleted ? kDefaultLayer : id;
  }

  bool isLayerVisible(String id) => _layers[id]?.visible ?? true;

  bool _shown(String? layer) => isLayerVisible(resolveLayer(layer));

  /// Alle Stempel inkl. gelöschter (für Speichern/Sync).
  Iterable<Stamp> get allStamps => _stamps.values;

  /// Sichtbare Stempel einer Seite (nicht gelöscht, Ebene eingeblendet).
  List<Stamp> visibleStampsOn(int page) =>
      _stamps.values.where((s) => s.page == page && !s.deleted && _shown(s.layer)).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  void putStamp(Stamp s) => _stamps[s.id] = s;

  Stamp? stamp(String id) => _stamps[id];

  /// Alle Text-Notizen inkl. gelöschter (für Speichern/Sync).
  Iterable<TextNote> get allTexts => _texts.values;

  /// Sichtbare Text-Notizen einer Seite (nicht gelöscht, Ebene eingeblendet).
  List<TextNote> visibleTextsOn(int page) =>
      _texts.values.where((t) => t.page == page && !t.deleted && _shown(t.layer)).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  void putText(TextNote t) => _texts[t.id] = t;

  TextNote? text(String id) => _texts[id];

  /// Alle Striche inkl. gelöschter (für Speichern/Sync).
  Iterable<Stroke> get allStrokes => _strokes.values;

  /// Sichtbare Striche einer Seite (nicht gelöscht, Ebene eingeblendet),
  /// in Zeichenreihenfolge.
  List<Stroke> visibleStrokesOn(int page) {
    final list = _strokes.values.where((s) => s.page == page && !s.deleted && _shown(s.layer)).toList()
      ..sort((a, b) {
        final c = a.createdAt.compareTo(b.createdAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    return list;
  }

  bool get isEmpty =>
      _strokes.values.every((s) => s.deleted) &&
      _texts.values.every((t) => t.deleted) &&
      _stamps.values.every((s) => s.deleted);

  void put(Stroke stroke) => _strokes[stroke.id] = stroke;

  Stroke? operator [](String id) => _strokes[id];

  /// Führt Anmerkungen eines anderen Geräts mit diesen zusammen.
  ///
  /// Regeln (ein einfaches, konfliktfreies Verfahren):
  /// * Striche, die nur auf einer Seite existieren, werden übernommen.
  /// * Ist ein Strich irgendwo gelöscht, bleibt er gelöscht.
  /// * Sonst gewinnt die Version mit der jüngsten Änderung.
  ///
  /// Das Ergebnis ist unabhängig von der Reihenfolge: `a.merge(b)` und
  /// `b.merge(a)` ergeben denselben Stand.
  static ScoreAnnotations merge(ScoreAnnotations a, ScoreAnnotations b) {
    final result = ScoreAnnotations(a.allStrokes, a.allTexts, a.allStamps, a.allLayers);
    for (final other in b.allLayers) {
      final mine = result._layers[other.id];
      result.putLayer(mine == null ? other : _pickLayer(mine, other));
    }
    for (final other in b.allStamps) {
      final mine = result.stamp(other.id);
      result.putStamp(mine == null ? other : _pickStamp(mine, other));
    }
    for (final other in b.allStrokes) {
      final mine = result[other.id];
      result.put(mine == null ? other : _pick(mine, other));
    }
    for (final other in b.allTexts) {
      final mine = result.text(other.id);
      result.putText(mine == null ? other : _pickText(mine, other));
    }
    return result;
  }

  static Stroke _pick(Stroke a, Stroke b) {
    if (a.deleted != b.deleted) return a.deleted ? a : b;
    final c = a.lastChange.compareTo(b.lastChange);
    if (c != 0) return c > 0 ? a : b;
    return a;
  }

  static AnnotationLayer _pickLayer(AnnotationLayer a, AnnotationLayer b) {
    if (a.deleted != b.deleted) return a.deleted ? a : b;
    final c = a.lastChange.compareTo(b.lastChange);
    if (c != 0) return c > 0 ? a : b;
    return a.name.compareTo(b.name) >= 0 ? a : b;
  }

  static Stamp _pickStamp(Stamp a, Stamp b) {
    if (a.deleted != b.deleted) return a.deleted ? a : b;
    final c = a.lastChange.compareTo(b.lastChange);
    if (c != 0) return c > 0 ? a : b;
    return a.id.compareTo(b.id) >= 0 ? a : b;
  }

  static TextNote _pickText(TextNote a, TextNote b) {
    if (a.deleted != b.deleted) return a.deleted ? a : b;
    final c = a.lastChange.compareTo(b.lastChange);
    if (c != 0) return c > 0 ? a : b;
    return a.text.compareTo(b.text) >= 0 ? a : b; // gleiche Zeit: eindeutig entscheiden
  }

  Map<String, dynamic> toJson() => {
    'format': 'volti-annotations',
    'version': formatVersion,
    'strokes': (_strokes.values.toList()..sort((a, b) => a.id.compareTo(b.id))).map((s) => s.toJson()).toList(),
    if (_stamps.isNotEmpty)
      'stamps': (_stamps.values.toList()..sort((a, b) => a.id.compareTo(b.id))).map((t) => t.toJson()).toList(),
    if (_layers.isNotEmpty)
      'layers': (_layers.values.toList()..sort((a, b) => a.id.compareTo(b.id))).map((l) => l.toJson()).toList(),
    if (_texts.isNotEmpty)
      'texts': (_texts.values.toList()..sort((a, b) => a.id.compareTo(b.id))).map((t) => t.toJson()).toList(),
  };

  static ScoreAnnotations fromJson(Map<String, dynamic> json) {
    final strokes = (json['strokes'] as List<dynamic>? ?? const []).map(
      (s) => Stroke.fromJson(s as Map<String, dynamic>),
    );
    final texts = (json['texts'] as List<dynamic>? ?? const []).map(
      (t) => TextNote.fromJson(t as Map<String, dynamic>),
    );
    final stamps = (json['stamps'] as List<dynamic>? ?? const []).map((t) => Stamp.fromJson(t as Map<String, dynamic>));
    final layers = (json['layers'] as List<dynamic>? ?? const []).map(
      (l) => AnnotationLayer.fromJson(l as Map<String, dynamic>),
    );
    return ScoreAnnotations(strokes, texts, stamps, layers);
  }
}
