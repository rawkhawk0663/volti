import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'backup.dart';

/// Automatische Sicherung: einmal pro Woche eine ganze Sicherung
/// ([LibraryBackup]) in einen Ordner, die ältesten werden weggeräumt.
class AutoBackup {
  AutoBackup._();

  static const interval = Duration(days: 7);

  /// So viele automatische Sicherungen bleiben liegen.
  static const keep = 3;

  static const prefix = 'Volti-Auto-Sicherung-';

  static String fileName(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '$prefix${d.year}-${two(d.month)}-${two(d.day)}.zip';
  }

  /// Ist eine neue Sicherung fällig?
  static bool isDue(DateTime? last, DateTime now) => last == null || now.difference(last) >= interval;

  /// Sicherung von [root] nach [dir] schreiben (im Hintergrund) und alte
  /// automatische Sicherungen wegräumen. Gibt den Pfad zurück.
  static Future<String> run(String root, String dir, {DateTime? now}) async {
    final d = now ?? DateTime.now();
    await Directory(dir).create(recursive: true);
    final path = p.join(dir, fileName(d));
    await Isolate.run(() => LibraryBackup.create(root, path));
    await prune(dir);
    return path;
  }

  /// Nur Voltis eigene automatische Sicherungen werden gelöscht, die
  /// jüngsten [keep] bleiben. Von Hand erstellte bleiben immer.
  static Future<void> prune(String dir) async {
    final files = <File>[];
    await for (final e in Directory(dir).list(followLinks: false)) {
      final name = p.basename(e.path);
      if (e is File && name.startsWith(prefix) && name.endsWith('.zip')) files.add(e);
    }
    // Der Name enthält das Datum, also sortiert er richtig.
    files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    for (final f in files.skip(keep)) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }
}
