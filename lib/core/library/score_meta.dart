import 'package:path/path.dart' as p;

/// Infos zu einem Notenstück: Titel, Komponist, Genre, Tags usw.
///
/// Jedes Feld merkt sich, wann es zuletzt geändert wurde. Beim Sync gewinnt
/// pro Feld die jüngste Änderung. Ändert man auf dem Surface den Komponisten
/// und auf dem Laptop das Genre, bleiben also beide Änderungen erhalten.
class ScoreMeta {
  ScoreMeta([Map<String, MetaValue>? fields]) : _fields = {...?fields};

  final Map<String, MetaValue> _fields;

  static const title = 'title';
  static const composer = 'composer';
  static const genre = 'genre';
  static const tags = 'tags';
  static const key = 'key';
  static const notes = 'notes';

  /// Ordner in der Bibliothek (ID, leer = oberste Ebene).
  static const folder = 'folder';

  /// Notizblatt einer Setlist (leeres Blatt zum Beschriften, true).
  static const sheet = 'sheet';

  /// Vorlage für leere Seiten dieses Stücks (z. B. Notenlinien bei einem
  /// Notizblatt, Name aus `Paper`).
  static const paper = 'paper';

  /// Tempo in Schlägen pro Minute (für das Metronom).
  static const tempo = 'tempo';

  /// Schläge pro Takt (für die Betonung im Metronom, z. B. 4 bei 4/4).
  static const beats = 'beats';

  /// Zugeordnete Aufnahme: Dateiname in `.volti/audio/` (z. B. `<id>.mp3`).
  static const audio = 'audio';

  /// Ursprünglicher Name der Aufnahme (nur zur Anzeige).
  static const audioName = 'audioName';

  Map<String, MetaValue> get fields => Map.unmodifiable(_fields);

  bool get isEmpty => _fields.isEmpty;

  String? text(String field) {
    final v = _fields[field]?.value;
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }

  List<String> get tagList {
    final v = _fields[tags]?.value;
    return v is List ? v.cast<String>() : const [];
  }

  /// Setzt ein Feld (nur wenn sich der Wert wirklich ändert).
  void set(String field, Object? value, {DateTime? at}) {
    final normalized = switch (value) {
      String s => s.trim(),
      List l => l.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toSet().toList()..sort(),
      _ => value,
    };
    if (_same(_fields[field]?.value, normalized)) return;
    _fields[field] = MetaValue(normalized, at ?? DateTime.now().toUtc());
  }

  static bool _same(Object? a, Object? b) {
    if (a is List && b is List) return a.length == b.length && a.indexed.every((e) => e.$2 == b[e.$1]);
    if ((a == null || a == '') && (b == null || b == '' || (b is List && b.isEmpty))) return true;
    return a == b;
  }

  static ScoreMeta merge(ScoreMeta a, ScoreMeta b) {
    final result = ScoreMeta(a._fields);
    for (final e in b._fields.entries) {
      final mine = result._fields[e.key];
      if (mine == null || e.value.changed.isAfter(mine.changed)) {
        result._fields[e.key] = e.value;
      }
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
    for (final e in (_fields.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
      e.key: {'v': e.value.value, 't': e.value.changed.toUtc().toIso8601String()},
  };

  static ScoreMeta fromJson(Map<String, dynamic>? json) {
    if (json == null) return ScoreMeta();
    return ScoreMeta({
      for (final e in json.entries)
        if (e.value is Map) e.key: MetaValue((e.value as Map)['v'], DateTime.parse((e.value as Map)['t'] as String)),
    });
  }
}

class MetaValue {
  const MetaValue(this.value, this.changed);
  final Object? value;
  final DateTime changed;
}

/// Vorschlag für Titel und Komponist aus dem Dateinamen, solange nichts
/// eingetragen ist: "Bach - Cellosuite 1.pdf" → Komponist "Bach",
/// Titel "Cellosuite 1".
({String title, String? composer}) guessFromFileName(String path) {
  final name = p.basenameWithoutExtension(path).replaceAll('_', ' ').trim();
  final parts = name.split(RegExp(r'\s+[-–]\s+'));
  if (parts.length >= 2 && parts.first.isNotEmpty) {
    return (title: parts.sublist(1).join(' – '), composer: parts.first);
  }
  return (title: name, composer: null);
}
