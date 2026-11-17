import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Ein Speicherort, mit dem Volti seinen Datenordner abgleicht.
///
/// Heute ist das ein Ordner (z. B. in Proton Drive). Später kann hier eine
/// direkte Anbindung an Dropbox oder Google Drive dazukommen, ohne dass sich
/// der Abgleich selbst ändert.
abstract class SyncStore {
  /// Alle für Volti relevanten Dateien: relativer Pfad ('/' als Trenner).
  Future<Set<String>> list();

  Future<bool> exists(String rel);
  Future<String> readString(String rel);
  Future<void> writeString(String rel, String content);
  Stream<List<int>> openRead(String rel);
  Future<void> writeStream(String rel, Stream<List<int>> data);
  Future<void> delete(String rel);

  /// Pfad der Datei auf diesem Gerät, falls der Speicher ein Ordner ist
  /// (dann kann ganz kopiert statt gelesen werden). Sonst null.
  String? localPath(String rel);
}

/// Welche Dateien zum Abgleich gehören.
bool isSyncedPath(String rel) {
  if (rel.endsWith('.tmp') || rel.contains('.defekt-')) return false;
  final parts = rel.split('/');
  if (parts.length == 2 && parts[0] == 'Noten') {
    final name = parts[1].toLowerCase();
    return name.endsWith('.pdf') || name.endsWith('.json');
  }
  if (parts.length == 3 && parts[0] == '.volti' && parts[1] == 'setlists') return parts[2].endsWith('.json');
  // Unterricht: eine Datei pro Schüler:in
  if (parts.length == 3 && parts[0] == '.volti' && parts[1] == 'students') return parts[2].endsWith('.json');
  // Bilder der eigenen Stempel
  if (parts.length == 3 && parts[0] == '.volti' && parts[1] == 'stamps') return parts[2].endsWith('.png');
  return rel == '.volti/library.json' ||
      rel == '.volti/presets.json' ||
      rel == '.volti/stamps.json' ||
      rel == '.volti/folders.json' ||
      rel == '.volti/setlist-folders.json' ||
      rel == '.volti/teaching.json' ||
      rel == '.volti/todos.json';
}

/// Ein gewöhnlicher Ordner als Sync-Ziel.
class FolderSyncStore implements SyncStore {
  FolderSyncStore(this.root);
  final String root;

  String _abs(String rel) => p.joinAll([root, ...rel.split('/')]);

  @override
  Future<Set<String>> list() async {
    final result = <String>{};
    for (final sub in ['Noten', '.volti']) {
      final dir = Directory(p.join(root, sub));
      if (!await dir.exists()) continue;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final rel = p.split(p.relative(e.path, from: root)).join('/');
        if (isSyncedPath(rel)) result.add(rel);
      }
    }
    return result;
  }

  @override
  Future<bool> exists(String rel) => File(_abs(rel)).exists();

  @override
  String? localPath(String rel) => _abs(rel);

  /// Lesen; verweigert der Cloud-Dienst das (Proton Drive gibt Dateien beim
  /// Lesen in Stücken manchmal nicht frei), über eine Kopie – so wie der
  /// Import, der beim Besitzer funktioniert.
  @override
  Future<String> readString(String rel) async {
    try {
      return await File(_abs(rel)).readAsString();
    } on FileSystemException {
      final tmp = File(p.join(Directory.systemTemp.path, 'volti-sync-${DateTime.now().microsecondsSinceEpoch}.tmp'));
      try {
        await File(_abs(rel)).copy(tmp.path);
        return await tmp.readAsString();
      } finally {
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
      }
    }
  }

  /// Eine ganze Datei hierher kopieren (erst als .tmp, dann umbenennen).
  Future<void> copyFromFile(String rel, String source) async {
    final target = File(_abs(rel));
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp');
    try {
      await File(source).copy(tmp.path);
      await tmp.rename(target.path);
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<void> writeString(String rel, String content) => writeStream(rel, Stream.value(utf8.encode(content)));

  @override
  Stream<List<int>> openRead(String rel) => File(_abs(rel)).openRead();

  @override
  Future<void> writeStream(String rel, Stream<List<int>> data) async {
    final target = File(_abs(rel));
    await target.parent.create(recursive: true);
    // Erst vollständig schreiben, dann umbenennen: Der Cloud-Dienst sieht so
    // nie eine halbe Datei.
    final tmp = File('${target.path}.tmp');
    IOSink? sink = tmp.openWrite();
    try {
      await sink.addStream(data);
      await sink.flush();
      await sink.close();
      sink = null;
      await tmp.rename(target.path);
    } catch (_) {
      // Halbe Datei wegräumen; der ursprüngliche Fehler zählt.
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<void> delete(String rel) async {
    final f = File(_abs(rel));
    if (await f.exists()) await f.delete();
  }
}
