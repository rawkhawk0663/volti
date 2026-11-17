import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Eine Aufgabe (To-Do) im Unterricht, auf Wunsch zu einer Schülerin, einem
/// Schüler oder einer Gruppe gehörend ([student]).
class Todo {
  Todo({
    required this.id,
    required this.text,
    required this.created,
    required this.modified,
    this.due,
    this.student,
    this.done = false,
    this.deleted = false,
  });

  factory Todo.create(String text, {DateTime? due, String? student}) {
    final now = DateTime.now().toUtc();
    return Todo(id: const Uuid().v4(), text: text.trim(), created: now, modified: now, due: due, student: student);
  }

  final String id;
  String text;

  /// Fällig am (Tag, ohne Uhrzeit), null = ohne Termin.
  DateTime? due;

  /// Kartei (Student-ID), null = allgemein.
  String? student;
  bool done;
  final DateTime created;
  DateTime modified;
  bool deleted;

  void touch() => modified = DateTime.now().toUtc();

  /// Überfällig (Termin vor heute, noch offen).
  bool overdue(DateTime now) => !done && due != null && due!.isBefore(DateTime(now.year, now.month, now.day));

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    if (due != null) 'due': _day(due!),
    'student': ?student,
    if (done) 'done': true,
    'created': created.toUtc().toIso8601String(),
    'modified': modified.toUtc().toIso8601String(),
    if (deleted) 'deleted': true,
  };

  static Todo? tryFromJson(Object? o) {
    try {
      final j = o as Map<String, dynamic>;
      DateTime? due;
      if (j['due'] is String) {
        final x = (j['due'] as String).split('-').map(int.parse).toList();
        due = DateTime(x[0], x[1], x[2]);
      }
      return Todo(
        id: j['id'] as String,
        text: j['text'] as String? ?? '',
        due: due,
        student: j['student'] as String?,
        done: j['done'] as bool? ?? false,
        created: DateTime.parse(j['created'] as String),
        modified: DateTime.parse(j['modified'] as String),
        deleted: j['deleted'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Alle To-Dos in `Bibliothek/.volti/todos.json` (Format `volti-todos` v1).
/// Beim Sync wird pro Eintrag zusammengeführt (jüngste Fassung gewinnt,
/// gelöscht bleibt gelöscht).
class TodoStore {
  TodoStore._();

  static const file = '.volti/todos.json';

  static Map<String, Todo> decode(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    return {for (final t in (j['todos'] as List? ?? const []).map(Todo.tryFromJson).nonNulls) t.id: t};
  }

  static String encode(Map<String, Todo> todos) {
    final list = todos.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return const JsonEncoder.withIndent(' ').convert({
      'format': 'volti-todos',
      'version': 1,
      'todos': [for (final t in list) t.toJson()],
    });
  }

  static Map<String, Todo> merge(Map<String, Todo> a, Map<String, Todo> b) => {
    for (final id in {...a.keys, ...b.keys})
      id: a[id] == null
          ? b[id]!
          : b[id] == null
          ? a[id]!
          : (b[id]!.modified.isAfter(a[id]!.modified) ? b[id]! : a[id]!),
  };

  static File _file(String root) => File(p.joinAll([root, ...file.split('/')]));

  static Future<Map<String, Todo>> load(String root) async {
    try {
      final f = _file(root);
      if (!await f.exists()) return {};
      return decode(await f.readAsString());
    } catch (_) {
      return {};
    }
  }

  /// Speichern, mit dem Stand auf der Festplatte zusammengeführt.
  static Future<Map<String, Todo>> save(String root, Map<String, Todo> todos) async {
    final merged = merge(await load(root), todos);
    final f = _file(root);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(encode(merged), flush: true);
    await tmp.rename(f.path);
    return merged;
  }
}
