import 'dart:io';

import 'package:path/path.dart' as p;

import 'setlist.dart';
import 'sidecar_store.dart';

/// Ergebnis eines Imports.
class ImportResult {
  /// Neu importierte Stücke: Originalpfad → Pfad relativ zur Bibliothek.
  final Map<String, String> added = {};

  /// Bereits vorhandene Stücke (gleicher Name und gleiche Grösse):
  /// Originalpfad → vorhandener relativer Pfad.
  final Map<String, String> alreadyThere = {};

  /// Dateien, die nicht kopiert werden konnten.
  final List<String> failed = [];
}

/// Holt PDFs in Voltis eigenen Datenordner.
///
/// Aufbau des Datenordners:
///
///     Bibliothek/
///       Noten/
///         Bach - Cellosuite 1.pdf
///         Bach - Cellosuite 1.pdf.volti.json   ← Infos und Anmerkungen
///       .volti/setlists/…                      ← Setlists
///
/// Die Originaldateien bleiben unverändert dort, wo sie waren.
class ScoreImporter {
  ScoreImporter(this.libraryRoot);

  final String libraryRoot;

  static const notesFolder = 'Noten';

  String get notesDir => p.join(libraryRoot, notesFolder);

  Future<ImportResult> importFiles(Iterable<String> sources) async {
    final result = ImportResult();
    await Directory(notesDir).create(recursive: true);
    for (final src in sources) {
      try {
        if (p.isWithin(libraryRoot, src)) {
          result.alreadyThere[src] = _rel(src);
          continue;
        }
        final size = await File(src).length();
        final name = _cleanName(p.basename(src));
        var target = p.join(notesDir, name);
        var n = 2;
        var duplicate = false;
        while (await File(target).exists()) {
          if (await File(target).length() == size) {
            duplicate = true;
            break;
          }
          target = p.join(notesDir, '${p.basenameWithoutExtension(name)} ($n).pdf');
          n++;
        }
        if (duplicate) {
          result.alreadyThere[src] = _rel(target);
          continue;
        }
        await File(src).copy(target);
        // Infos/Anmerkungen aus Volti (falls vorhanden) mitnehmen.
        final side = File('$src${SidecarStore.suffix}');
        if (await side.exists()) await side.copy('$target${SidecarStore.suffix}');
        result.added[src] = _rel(target);
      } catch (_) {
        result.failed.add(src);
      }
    }
    return result;
  }

  /// Alle PDFs in einem Ordner (inkl. Unterordnern), z. B. um eine
  /// bestehende Notensammlung auf einmal zu importieren.
  static Future<List<String>> findPdfs(String folder) async {
    final result = <String>[];
    Future<void> walk(Directory d) async {
      List<FileSystemEntity> children;
      try {
        children = await d.list(followLinks: false).toList();
      } catch (_) {
        return;
      }
      for (final c in children) {
        final name = p.basename(c.path);
        if (name.startsWith('.') || name.startsWith(r'$')) continue;
        if (c is Directory) {
          await walk(c);
        } else if (c is File && name.toLowerCase().endsWith('.pdf')) {
          result.add(c.path);
        }
      }
    }

    await walk(Directory(folder));
    result.sort();
    return result;
  }

  String _rel(String path) => p.split(p.relative(path, from: libraryRoot)).join('/');

  /// Endung vereinheitlichen (".PDF" → ".pdf").
  static String _cleanName(String name) =>
      name.toLowerCase().endsWith('.pdf') ? '${name.substring(0, name.length - 4)}.pdf' : '$name.pdf';
}

/// Übernimmt eine Bibliothek aus Version 0.1.2 (damals ein selbst gewählter
/// Ordner) in den neuen Datenordner: PDFs samt Infos/Anmerkungen und
/// Setlists. Der alte Ordner bleibt unverändert.
Future<ImportResult> migrateLegacyLibrary({required String oldRoot, required String newRoot}) async {
  final importer = ScoreImporter(newRoot);
  final result = await importer.importFiles(await ScoreImporter.findPdfs(oldRoot));
  final mapping = <String, String>{
    for (final e in {...result.alreadyThere, ...result.added}.entries)
      p.split(p.relative(e.key, from: oldRoot)).join('/'): e.value,
  };
  final newStore = SetlistStore(newRoot);
  final existing = {for (final s in await newStore.loadAll()) s.id};
  for (final s in await SetlistStore(oldRoot).loadAll()) {
    if (existing.contains(s.id)) continue;
    final items = [
      for (final i in s.items)
        if (mapping[i.relativePath] != null) SetlistItem(id: i.id, relativePath: mapping[i.relativePath]!),
    ];
    await newStore.save(Setlist(id: s.id, name: s.name, items: items, modified: s.modified));
  }
  return result;
}
