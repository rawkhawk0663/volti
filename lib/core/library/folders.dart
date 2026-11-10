import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Ein Ordner in der Bibliothek (z. B. ein Projekt).
///
/// Ordner sind nur eine Liste, die Volti sich merkt – die PDFs bleiben in
/// `Noten/` liegen. Ein Stück zeigt über sein Info-Feld `folder` auf seinen
/// Ordner. So gehen Setlists, Anmerkungen und der Abgleich beim Umsortieren
/// nie kaputt.
class ScoreFolder {
  ScoreFolder({required this.id, required this.name, this.parent, required this.modified, this.deleted = false});

  final String id;
  final String name;

  /// Übergeordneter Ordner (null = oberste Ebene).
  final String? parent;
  final DateTime modified;

  /// Gelöscht (bleibt als Grabstein, damit der Abgleich ihn nicht zurückholt).
  final bool deleted;

  static const _uuid = Uuid();

  factory ScoreFolder.create(String name, {String? parent}) =>
      ScoreFolder(id: _uuid.v4(), name: name.trim(), parent: parent, modified: DateTime.now().toUtc());

  ScoreFolder copyWith({String? name, String? Function()? parent, bool? deleted}) => ScoreFolder(
    id: id,
    name: name ?? this.name,
    parent: parent == null ? this.parent : parent(),
    modified: DateTime.now().toUtc(),
    deleted: deleted ?? this.deleted,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (parent != null) 'parent': parent,
    'modified': modified.toUtc().toIso8601String(),
    if (deleted) 'deleted': true,
  };

  static ScoreFolder fromJson(Map<String, dynamic> j) => ScoreFolder(
    id: j['id'] as String,
    name: j['name'] as String? ?? 'Ordner',
    parent: j['parent'] as String?,
    modified: DateTime.tryParse(j['modified'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    deleted: j['deleted'] == true,
  );
}

/// Zwei Fassungen der Ordnerliste zusammenführen: pro Ordner gewinnt die
/// jüngste Änderung (auch beim Löschen – so kann "Rückgängig" einen
/// gelöschten Ordner zurückholen).
List<ScoreFolder> mergeFolders(List<ScoreFolder> a, List<ScoreFolder> b) {
  final byId = <String, ScoreFolder>{for (final f in a) f.id: f};
  for (final f in b) {
    final mine = byId[f.id];
    if (mine == null || f.modified.isAfter(mine.modified)) byId[f.id] = f;
  }
  return byId.values.toList()..sort((x, y) => x.id.compareTo(y.id));
}

/// Die Ordner als Baum: wer liegt worin, und wo landet ein Stück, dessen
/// Ordner gelöscht ist.
class FolderTree {
  FolderTree(Iterable<ScoreFolder> folders) : _all = {for (final f in folders) f.id: f};

  final Map<String, ScoreFolder> _all;

  ScoreFolder? byId(String? id) => id == null ? null : _all[id];

  /// Nicht gelöschte Ordner.
  Iterable<ScoreFolder> get live => _all.values.where((f) => !f.deleted);

  /// Wo etwas tatsächlich liegt: Ist sein Ordner gelöscht oder unbekannt,
  /// rutscht es eine Ebene höher (bis zur obersten Ebene = null). Schutz
  /// gegen Kreise (z. B. wenn zwei Geräte gleichzeitig verschieben).
  String? resolve(String? id) {
    final seen = <String>{};
    var cur = id;
    while (cur != null) {
      if (!seen.add(cur)) return null;
      final f = _all[cur];
      if (f == null) return null;
      if (!f.deleted) return cur;
      cur = f.parent;
    }
    return null;
  }

  /// Übergeordneter (nicht gelöschter) Ordner eines Ordners.
  String? parentOf(String id) {
    final f = _all[id];
    if (f == null) return null;
    final parent = resolve(f.parent);
    // Kreis: so tun, als läge der Ordner zuoberst.
    if (parent != null && isInside(parent, id)) return null;
    return parent;
  }

  /// Liegt [id] in [ancestor] (oder ist es derselbe Ordner)?
  bool isInside(String? id, String ancestor) {
    final seen = <String>{};
    var cur = id;
    while (cur != null && seen.add(cur)) {
      if (cur == ancestor) return true;
      cur = resolve(_all[cur]?.parent);
    }
    return false;
  }

  /// Unterordner (nach Name sortiert). [parent] null = oberste Ebene.
  List<ScoreFolder> children(String? parent) {
    final list = [
      for (final f in live)
        if (parentOf(f.id) == parent) f,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Weg von oben bis zu [id] (für die Brotkrümel-Leiste).
  List<ScoreFolder> pathTo(String? id) {
    final result = <ScoreFolder>[];
    final seen = <String>{};
    var cur = resolve(id);
    while (cur != null && seen.add(cur)) {
      result.insert(0, _all[cur]!);
      cur = parentOf(cur);
    }
    return result;
  }

  /// Alle Ordner der Reihe nach wie in einem Baum (oben zuerst), mit Tiefe.
  List<(ScoreFolder, int)> outline() {
    final out = <(ScoreFolder, int)>[];
    void walk(String? parent, int depth) {
      for (final f in children(parent)) {
        out.add((f, depth));
        walk(f.id, depth + 1);
      }
    }

    walk(null, 0);
    return out;
  }
}

/// Liest und schreibt `Bibliothek/.volti/folders.json` bzw.
/// `.volti/setlist-folders.json` (Format `volti-folders` v1).
class FolderStore {
  FolderStore(this.libraryRoot, {this.file = scoresFile});
  final String libraryRoot;

  /// Ordner der Bibliothek bzw. der Setlists (zwei getrennte Bäume).
  static const scoresFile = '.volti/folders.json';
  static const setlistsFile = '.volti/setlist-folders.json';
  static const files = {scoresFile, setlistsFile};

  final String file;

  File get _file => File(p.joinAll([libraryRoot, ...file.split('/')]));

  Future<List<ScoreFolder>> load() async {
    try {
      if (!await _file.exists()) return [];
      return decode(await _file.readAsString());
    } catch (_) {
      return [];
    }
  }

  static List<ScoreFolder> decode(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    return [
      for (final e in j['folders'] as List<dynamic>? ?? const []) ScoreFolder.fromJson(e as Map<String, dynamic>),
    ];
  }

  static String encode(List<ScoreFolder> folders) => const JsonEncoder.withIndent(' ').convert({
    'format': 'volti-folders',
    'version': 1,
    'modified': DateTime.now().toUtc().toIso8601String(),
    'folders': [for (final f in folders) f.toJson()],
  });

  Future<void> save(List<ScoreFolder> folders) async {
    await _file.parent.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(encode(folders), flush: true);
    await tmp.rename(_file.path);
  }
}
