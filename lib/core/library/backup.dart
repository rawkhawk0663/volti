import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../sync/sync_engine.dart';
import '../sync/sync_store.dart';

/// Sicherung der ganzen Bibliothek in einer einzigen ZIP-Datei: Noten (PDFs),
/// Infos und Anmerkungen, Setlists, Ordner, eigene Stempel und Stift-Vorlagen.
///
/// Einspielen **ersetzt nichts**: Die Sicherung wird wie ein zweites Gerät
/// abgeglichen – was fehlt, kommt dazu, Infos und Anmerkungen werden
/// zusammengeführt (jüngste Änderung gewinnt), gelöscht wird nichts.
class LibraryBackup {
  LibraryBackup._();

  /// Kennzeichnet eine Volti-Sicherung (im ZIP ganz oben).
  static const markerFile = 'volti-sicherung.json';

  /// Dateien der Bibliothek, die in die Sicherung gehören (wie beim Sync).
  static Future<List<String>> _files(String root) async {
    final dir = Directory(root);
    if (!await dir.exists()) return const [];
    final out = <String>[];
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.split(p.relative(e.path, from: root)).join('/');
      if (isSyncedPath(rel)) out.add(rel);
    }
    out.sort();
    return out;
  }

  /// Erstellt die Sicherung in [zipPath]. Gibt die Anzahl der Noten zurück.
  /// [onProgress] meldet (fertig, gesamt).
  static Future<int> create(String root, String zipPath, {void Function(int done, int total)? onProgress}) async {
    final files = await _files(root);
    final tmp = '$zipPath.tmp';
    final zip = ZipFileEncoder()..create(tmp, level: ZipFileEncoder.store);
    try {
      final pdfs = files.where((f) => f.toLowerCase().endsWith('.pdf')).length;
      final info = utf8.encode(
        const JsonEncoder.withIndent(' ').convert({
          'format': 'volti-backup',
          'version': 1,
          'created': DateTime.now().toUtc().toIso8601String(),
          'scores': pdfs,
          'files': files.length,
        }),
      );
      zip.addArchiveFile(ArchiveFile(markerFile, info.length, info));
      for (var i = 0; i < files.length; i++) {
        await zip.addFile(File(p.joinAll([root, ...files[i].split('/')])), files[i]);
        onProgress?.call(i + 1, files.length);
      }
      await zip.close();
      final target = File(zipPath);
      if (await target.exists()) await target.delete();
      await File(tmp).rename(zipPath);
      return pdfs;
    } catch (_) {
      try {
        await File(tmp).delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// Spielt eine Sicherung ein (zusammenführen, nichts löschen).
  /// [workDir]: Platz für das Auspacken (wird danach aufgeräumt).
  static Future<SyncReport> restore(String root, String zipPath, String workDir) async {
    final work = Directory(p.join(workDir, 'volti-sicherung-${DateTime.now().millisecondsSinceEpoch}'));
    await work.create(recursive: true);
    try {
      final unpacked = p.join(work.path, 'inhalt');
      await extractFileToDisk(zipPath, unpacked);
      if (!await File(p.join(unpacked, markerFile)).exists()) {
        throw const FormatException('Diese Datei ist keine Volti-Sicherung.');
      }
      final folder = FolderSyncStore(unpacked);
      await SyncEngine.initializeRemote(folder);
      // Eigene, leere Basis: Beim ersten Abgleich wird nie etwas gelöscht.
      // In die ausgepackte Sicherung wird nichts zurückgeschrieben.
      final engine = SyncEngine(
        localRoot: root,
        remote: _ReadOnly(folder),
        baseFile: File(p.join(work.path, 'basis.json')),
      );
      return await engine.run();
    } finally {
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    }
  }
}

/// Nur lesen: Schreiben und Löschen werden ignoriert.
class _ReadOnly implements SyncStore {
  _ReadOnly(this.inner);
  final SyncStore inner;

  @override
  Future<Set<String>> list() => inner.list();
  @override
  Future<bool> exists(String rel) => inner.exists(rel);
  @override
  Future<String> readString(String rel) => inner.readString(rel);
  @override
  Stream<List<int>> openRead(String rel) => inner.openRead(rel);
  @override
  Future<void> writeString(String rel, String content) async {}
  @override
  Future<void> writeStream(String rel, Stream<List<int>> data) async {}
  @override
  Future<void> delete(String rel) async {}
}
