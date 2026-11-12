import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../app/l10n.dart';

/// Eine Setlist: eine geordnete Liste von Stücken, z. B. für ein Konzert.
///
/// Stücke werden über ihren Pfad *relativ zum Bibliotheksordner* gespeichert.
/// So funktioniert die Setlist auf jedem Gerät, auch wenn der
/// Bibliotheksordner dort an einem anderen Ort liegt.
class Setlist {
  Setlist({required this.id, required this.name, required this.items, required this.modified, this.folder});

  factory Setlist.create(String name) =>
      Setlist(id: const Uuid().v4(), name: name.trim(), items: [], modified: DateTime.now().toUtc());

  final String id;
  String name;
  final List<SetlistItem> items;
  DateTime modified;

  /// Ordner bei den Setlists (ID, null = oberste Ebene).
  String? folder;

  void touch() => modified = DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
    'format': 'volti-setlist',
    'version': 1,
    'id': id,
    'name': name,
    'modified': modified.toUtc().toIso8601String(),
    if (folder != null) 'folder': folder,
    'items': [for (final i in items) i.toJson()],
  };

  static Setlist fromJson(Map<String, dynamic> json) => Setlist(
    id: json['id'] as String,
    name: json['name'] as String? ?? tr('Setlist', 'Setlist'),
    modified: DateTime.parse(json['modified'] as String),
    folder: json['folder'] as String?,
    items: [for (final i in json['items'] as List? ?? const []) SetlistItem.fromJson(i as Map<String, dynamic>)],
  );
}

class SetlistItem {
  SetlistItem({required this.id, required this.relativePath, this.bookmark, this.label});
  factory SetlistItem.create(String relativePath, {String? bookmark, String? label}) =>
      SetlistItem(id: const Uuid().v4(), relativePath: relativePath, bookmark: bookmark, label: label);

  /// Eigene ID pro Eintrag – dasselbe Stück darf mehrmals vorkommen.
  final String id;
  final String relativePath;

  /// Nur ein Lesezeichen-Bereich des Stücks (z. B. ein Lied aus einem
  /// Sammelband) und sein Name zum Anzeigen.
  final String? bookmark;
  final String? label;

  Map<String, dynamic> toJson() => {'id': id, 'path': relativePath, 'bookmark': ?bookmark, 'label': ?label};
  static SetlistItem fromJson(Map<String, dynamic> json) => SetlistItem(
    id: json['id'] as String,
    relativePath: json['path'] as String,
    bookmark: json['bookmark'] as String?,
    label: json['label'] as String?,
  );
}

/// Speichert Setlists als einzelne Dateien im versteckten Ordner
/// `.volti/setlists` innerhalb der Bibliothek. Damit werden sie zusammen
/// mit den Noten synchronisiert.
class SetlistStore {
  SetlistStore(this.libraryRoot);
  final String libraryRoot;

  Directory get _dir => Directory(p.join(libraryRoot, '.volti', 'setlists'));
  File _file(String id) => File(p.join(_dir.path, '$id.json'));

  Future<List<Setlist>> loadAll() async {
    if (!await _dir.exists()) return [];
    final result = <Setlist>[];
    await for (final f in _dir.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        result.add(Setlist.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>));
      } catch (_) {
        // Unlesbare Datei überspringen, nicht löschen.
      }
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  Future<void> save(Setlist s) async {
    await _dir.create(recursive: true);
    final file = _file(s.id);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(s.toJson()), flush: true);
    await tmp.rename(file.path);
  }

  Future<void> delete(Setlist s) async {
    final f = _file(s.id);
    if (await f.exists()) await f.delete();
  }
}
