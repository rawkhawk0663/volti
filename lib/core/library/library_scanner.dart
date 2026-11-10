import 'dart:io';

import 'package:path/path.dart' as p;

import 'score_meta.dart';
import 'sidecar_store.dart';

/// Ein Notenstück in der Bibliothek.
class ScoreEntry {
  ScoreEntry({
    required this.path,
    required this.relativePath,
    required this.meta,
    required this.modified,
    required this.hasAnnotations,
  });

  /// Vollständiger Pfad zum PDF auf diesem Gerät.
  final String path;

  /// Pfad relativ zum Bibliotheksordner (gleich auf allen Geräten).
  final String relativePath;

  ScoreMeta meta;
  final DateTime modified;
  bool hasAnnotations;

  String get title => meta.text(ScoreMeta.title) ?? guessFromFileName(path).title;
  String? get composer => meta.text(ScoreMeta.composer) ?? guessFromFileName(path).composer;
  String? get genre => meta.text(ScoreMeta.genre);
  List<String> get tags => meta.tagList;

  /// Tonart, z. B. „G-Dur“ (frei eingetragen, null = keine).
  String? get musicalKey => meta.text(ScoreMeta.key);

  /// Tempo (Schläge pro Minute) und Schläge pro Takt, falls eingetragen.
  int? get tempo => _int(ScoreMeta.tempo);
  int? get beats => _int(ScoreMeta.beats);
  int? _int(String field) {
    final v = meta.fields[field]?.value;
    return v is num && v > 0 ? v.round() : null;
  }

  /// Notizblatt einer Setlist? (erscheint nicht in der Bibliothek)
  bool get isSheet => meta.fields[ScoreMeta.sheet]?.value == true;

  /// Ordner in der Bibliothek (siehe `FolderTree.resolve`; null = keiner).
  String? get folderId => meta.text(ScoreMeta.folder);

  /// Unterordner innerhalb der Bibliothek ('' = oberste Ebene).
  String get folder {
    final d = p.dirname(relativePath);
    return d == '.' ? '' : d;
  }
}

/// Durchsucht den Bibliotheksordner (inkl. Unterordnern) nach PDFs.
///
/// Die PDFs selbst werden dabei nicht geöffnet – bei Cloud-Ordnern, deren
/// Dateien nur bei Bedarf heruntergeladen werden, würde das sonst alles
/// herunterladen. Gelesen werden nur die kleinen Volti-Zusatzdateien.
class LibraryScanner {
  const LibraryScanner({this.store = const SidecarStore()});
  final SidecarStore store;

  /// Ordner, die nicht durchsucht werden (versteckt bzw. Volti-intern).
  static bool _skipDir(String name) => name.startsWith('.') || name.startsWith(r'$');

  Future<List<ScoreEntry>> scan(String root) async {
    final result = <ScoreEntry>[];
    final dir = Directory(root);
    if (!await dir.exists()) return result;
    await for (final e in _walk(dir)) {
      final rel = p.relative(e.path, from: root);
      final sidecar = await store.load(e.path);
      DateTime modified;
      try {
        modified = (await e.stat()).modified;
      } catch (_) {
        modified = DateTime.fromMillisecondsSinceEpoch(0);
      }
      result.add(
        ScoreEntry(
          path: e.path,
          relativePath: p.split(rel).join('/'),
          meta: sidecar.meta,
          modified: modified,
          hasAnnotations: !sidecar.annotations.isEmpty,
        ),
      );
    }
    return result;
  }

  Stream<File> _walk(Directory dir) async* {
    List<FileSystemEntity> children;
    try {
      children = await dir.list(followLinks: false).toList();
    } catch (_) {
      return; // kein Zugriff – überspringen
    }
    for (final c in children) {
      final name = p.basename(c.path);
      if (c is Directory) {
        if (!_skipDir(name)) yield* _walk(c);
      } else if (c is File && name.toLowerCase().endsWith('.pdf') && !name.startsWith('.')) {
        yield c;
      }
    }
  }
}
