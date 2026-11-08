import 'stroke.dart';

/// Alle Anmerkungen zu einem Notenstück (einem PDF).
///
/// Das ist die Einheit, die als Datei neben dem PDF gespeichert und später
/// zwischen Geräten synchronisiert wird.
class ScoreAnnotations {
  ScoreAnnotations([Iterable<Stroke> strokes = const []]) {
    for (final s in strokes) {
      _strokes[s.id] = s;
    }
  }

  static const int formatVersion = 1;

  final Map<String, Stroke> _strokes = {};

  /// Alle Striche inkl. gelöschter (für Speichern/Sync).
  Iterable<Stroke> get allStrokes => _strokes.values;

  /// Sichtbare Striche einer Seite, in Zeichenreihenfolge.
  List<Stroke> visibleStrokesOn(int page) {
    final list = _strokes.values.where((s) => s.page == page && !s.deleted).toList()
      ..sort((a, b) {
        final c = a.createdAt.compareTo(b.createdAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    return list;
  }

  bool get isEmpty => _strokes.values.every((s) => s.deleted);

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
    final result = ScoreAnnotations(a.allStrokes);
    for (final other in b.allStrokes) {
      final mine = result[other.id];
      if (mine == null) {
        result.put(other);
      } else {
        result.put(_pick(mine, other));
      }
    }
    return result;
  }

  static Stroke _pick(Stroke a, Stroke b) {
    if (a.deleted != b.deleted) return a.deleted ? a : b;
    final c = a.lastChange.compareTo(b.lastChange);
    if (c != 0) return c > 0 ? a : b;
    return a;
  }

  Map<String, dynamic> toJson() => {
    'format': 'volti-annotations',
    'version': formatVersion,
    'strokes': (_strokes.values.toList()..sort((a, b) => a.id.compareTo(b.id))).map((s) => s.toJson()).toList(),
  };

  static ScoreAnnotations fromJson(Map<String, dynamic> json) {
    final strokes = (json['strokes'] as List<dynamic>? ?? const []).map(
      (s) => Stroke.fromJson(s as Map<String, dynamic>),
    );
    return ScoreAnnotations(strokes);
  }
}
