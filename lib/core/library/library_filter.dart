import 'library_scanner.dart';

enum ScoreSort { title, composer, recentlyOpened, recentlyAdded }

/// Filtert und sortiert die Stücke der Bibliothek.
List<ScoreEntry> filterScores(
  List<ScoreEntry> all, {
  String query = '',
  String? genre,
  String? tag,
  ScoreSort sort = ScoreSort.title,
  DateTime? Function(ScoreEntry)? lastOpened,
}) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  bool matches(ScoreEntry e) {
    if (genre != null && e.genre != genre) return false;
    if (tag != null && !e.tags.contains(tag)) return false;
    if (words.isEmpty) return true;
    final hay = [e.title, e.composer ?? '', e.genre ?? '', ...e.tags, e.relativePath].join(' ').toLowerCase();
    return words.every(hay.contains);
  }

  int byTitle(ScoreEntry a, ScoreEntry b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
  final list = all.where(matches).toList();
  switch (sort) {
    case ScoreSort.title:
      list.sort(byTitle);
    case ScoreSort.composer:
      list.sort((a, b) {
        final ca = a.composer?.toLowerCase(), cb = b.composer?.toLowerCase();
        if (ca != cb) {
          if (ca == null) return 1; // ohne Komponist ans Ende
          if (cb == null) return -1;
          return ca.compareTo(cb);
        }
        return byTitle(a, b);
      });
    case ScoreSort.recentlyOpened:
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      list.sort((a, b) {
        final c = (lastOpened?.call(b) ?? epoch).compareTo(lastOpened?.call(a) ?? epoch);
        return c != 0 ? c : byTitle(a, b);
      });
    case ScoreSort.recentlyAdded:
      list.sort((a, b) => b.modified.compareTo(a.modified));
  }
  return list;
}

/// Alle vorkommenden Werte (für Filter-Auswahl und Vorschläge beim Bearbeiten).
List<String> distinctValues(Iterable<ScoreEntry> all, Iterable<String?> Function(ScoreEntry) pick) {
  final set = <String>{};
  for (final e in all) {
    for (final v in pick(e)) {
      if (v != null && v.isNotEmpty) set.add(v);
    }
  }
  return set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}
