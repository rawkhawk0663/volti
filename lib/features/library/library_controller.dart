import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/app_settings.dart';
import '../../core/library/folders.dart';
import '../../core/library/library_scanner.dart';
import '../../core/library/score_importer.dart';
import '../../core/library/score_meta.dart';
import '../../core/library/setlist.dart';
import '../../core/library/sidecar_store.dart';

/// Hält den Zustand der Bibliothek: Stücke und Setlists.
///
/// Die Noten liegen in Voltis eigenem Datenordner ([root]). Neue Stücke
/// kommen über den Import hinein.
class LibraryController extends ChangeNotifier {
  LibraryController(this.settings, {required this.root});

  final AppSettings settings;

  /// Voltis Datenordner (siehe [ScoreImporter] für den Aufbau).
  final String root;

  final _scanner = const LibraryScanner();
  final _sidecars = const SidecarStore();
  late final _importer = ScoreImporter(root);
  late final _setlistStore = SetlistStore(root);
  late final _folderStore = FolderStore(root);

  List<ScoreEntry> _scores = [];
  List<ScoreEntry> get scores => _scores;

  List<Setlist> _setlists = [];
  List<Setlist> get setlists => _setlists;

  /// Ordner (inkl. gelöschter, als Grabsteine für den Abgleich).
  List<ScoreFolder> _folders = [];
  FolderTree _tree = FolderTree(const []);
  FolderTree get folders => _tree;

  bool _loading = false;
  bool get loading => _loading;

  /// Läuft gerade ein Import? (für die Fortschrittsanzeige)
  bool importing = false;

  String? error;

  /// Wird nach jeder Änderung an der Bibliothek aufgerufen (für den Sync).
  VoidCallback? onLocalChange;

  Future<void> init() async {
    await Directory(_importer.notesDir).create(recursive: true);
    await _migrateFromVersion012();
    await rescan();
  }

  /// Version 0.1.2 nutzte einen selbst gewählten Ordner. Dessen Inhalt wird
  /// einmalig übernommen (der alte Ordner bleibt, wie er ist).
  Future<void> _migrateFromVersion012() async {
    final old = settings.legacyLibraryRoot;
    if (old == null) return;
    try {
      if (await Directory(old).exists()) await migrateLegacyLibrary(oldRoot: old, newRoot: root);
      await settings.clearLegacyLibraryRoot();
    } catch (_) {
      // Beim nächsten Start nochmals versuchen.
    }
  }

  Future<void> rescan() async {
    _loading = true;
    error = null;
    notifyListeners();
    try {
      _scores = await _scanner.scan(root);
      _setlists = await _setlistStore.loadAll();
      _setFolders(await _folderStore.load());
    } catch (e) {
      error = 'Die Bibliothek konnte nicht gelesen werden: $e';
    }
    _loading = false;
    notifyListeners();
  }

  ScoreEntry? byRelativePath(String rel) {
    for (final s in _scores) {
      if (s.relativePath == rel) return s;
    }
    return null;
  }

  /// Kopiert PDFs in Voltis Datenordner. [folder]: Bibliotheks-Ordner, in den
  /// die neuen Stücke kommen (null = oberste Ebene).
  Future<ImportResult> importPdfs(List<String> paths, {String? folder}) async {
    importing = true;
    notifyListeners();
    ImportResult? result;
    try {
      result = await _importer.importFiles(paths);
      if (folder != null) {
        for (final rel in result.added.values) {
          final path = p.joinAll([root, ...rel.split('/')]);
          final meta = (await _sidecars.load(path)).meta;
          meta.set(ScoreMeta.folder, folder);
          await _sidecars.save(path, meta: meta);
        }
      }
      return result;
    } finally {
      importing = false;
      await rescan();
      onLocalChange?.call();
    }
  }

  /// Importiert alle PDFs eines Ordners (inkl. Unterordnern).
  Future<ImportResult> importFolder(String dir, {String? folder}) async =>
      importPdfs(await ScoreImporter.findPdfs(dir), folder: folder);

  // ------------------------------------------------------------- Ordner
  void _setFolders(List<ScoreFolder> list) {
    _folders = list;
    _tree = FolderTree(list);
  }

  Future<void> _saveFolders(List<ScoreFolder> list) async {
    _setFolders(list);
    await _folderStore.save(list);
    notifyListeners();
    onLocalChange?.call();
  }

  /// Ordner, in dem ein Stück liegt (null = oberste Ebene).
  String? folderOf(ScoreEntry e) => _tree.resolve(e.folderId);

  /// Stücke direkt in einem Ordner (ohne Unterordner).
  List<ScoreEntry> scoresIn(String? folder) => [
    for (final s in _scores)
      if (folderOf(s) == folder) s,
  ];

  /// Anzahl Stücke in einem Ordner samt Unterordnern.
  int countIn(String folder) => _scores.where((s) {
    final f = folderOf(s);
    return f != null && _tree.isInside(f, folder);
  }).length;

  Future<ScoreFolder> createFolder(String name, {String? parent}) async {
    final f = ScoreFolder.create(name, parent: parent);
    await _saveFolders([..._folders, f]);
    return f;
  }

  Future<void> _replaceFolder(ScoreFolder f) => _saveFolders([for (final x in _folders) x.id == f.id ? f : x]);

  Future<void> renameFolder(ScoreFolder f, String name) async {
    final cur = _tree.byId(f.id);
    if (cur != null && name.trim().isNotEmpty) await _replaceFolder(cur.copyWith(name: name.trim()));
  }

  /// Ordner verschieben. Gibt false zurück, wenn das Ziel in ihm selbst liegt.
  Future<bool> moveFolder(ScoreFolder f, String? parent) async {
    if (parent != null && _tree.isInside(parent, f.id)) return false;
    final cur = _tree.byId(f.id);
    if (cur == null) return false;
    await _replaceFolder(cur.copyWith(parent: () => parent));
    return true;
  }

  /// Löscht einen Ordner. Seine Stücke und Unterordner rutschen eine Ebene
  /// höher (sie werden nicht gelöscht).
  Future<void> deleteFolder(ScoreFolder f) async {
    final cur = _tree.byId(f.id);
    if (cur != null) await _replaceFolder(cur.copyWith(deleted: true));
  }

  /// Gelöschten Ordner zurückholen (Rückgängig).
  Future<void> restoreFolder(ScoreFolder f) async {
    final cur = _tree.byId(f.id);
    if (cur != null) await _replaceFolder(cur.copyWith(deleted: false));
  }

  /// Stücke in einen Ordner legen (null = oberste Ebene).
  Future<void> moveScores(Iterable<ScoreEntry> entries, String? folder) async {
    for (final e in entries) {
      final meta = ScoreMeta(e.meta.fields);
      meta.set(ScoreMeta.folder, folder ?? '');
      final saved = await _sidecars.save(e.path, meta: meta);
      e.meta = saved.meta;
    }
    notifyListeners();
    onLocalChange?.call();
  }

  /// Löscht ein Stück endgültig aus Volti (PDF, Infos und Anmerkungen) und
  /// entfernt es aus allen Setlists.
  Future<void> deleteScore(ScoreEntry entry) => deleteScores([entry]);

  /// Löscht mehrere Stücke auf einmal.
  Future<void> deleteScores(List<ScoreEntry> entries) async {
    final rels = {for (final e in entries) e.relativePath};
    final paths = {for (final e in entries) e.path};
    for (final entry in entries) {
      for (final f in [File(entry.path), File('${entry.path}${SidecarStore.suffix}')]) {
        if (await f.exists()) await f.delete();
      }
    }
    for (final s in _setlists) {
      final before = s.items.length;
      s.items.removeWhere((i) => rels.contains(i.relativePath));
      if (s.items.length != before) await saveSetlist(s);
    }
    _scores = _scores.where((e) => !paths.contains(e.path)).toList();
    notifyListeners();
    onLocalChange?.call();
  }

  /// Öffnet den Datenordner im Datei-Explorer (nur Windows/Linux).
  Future<void> revealDataFolder() async {
    if (Platform.isWindows) {
      await Process.run('explorer', [root]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [root]);
    }
  }

  Future<void> updateMeta(ScoreEntry entry, Map<String, Object?> changes) async {
    final meta = ScoreMeta(entry.meta.fields);
    changes.forEach(meta.set);
    final saved = await _sidecars.save(entry.path, meta: meta);
    entry.meta = saved.meta;
    notifyListeners();
    onLocalChange?.call();
  }

  /// Nach dem Schliessen eines Stücks: Infos/Anmerkungs-Status neu lesen.
  Future<void> refreshEntry(String path) async {
    for (final e in _scores) {
      if (e.path == path) {
        final s = await _sidecars.load(path);
        e.meta = s.meta;
        e.hasAnnotations = !s.annotations.isEmpty;
      }
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ Setlists
  Future<Setlist> createSetlist(String name) async {
    final s = Setlist.create(name);
    await _setlistStore.save(s);
    _setlists = [..._setlists, s]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    onLocalChange?.call();
    return s;
  }

  Future<void> saveSetlist(Setlist s) async {
    s.touch();
    await _setlistStore.save(s);
    _setlists = [..._setlists]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    onLocalChange?.call();
  }

  Future<void> deleteSetlist(Setlist s) async {
    await _setlistStore.delete(s);
    _setlists = _setlists.where((x) => x.id != s.id).toList();
    notifyListeners();
    onLocalChange?.call();
  }

  Future<void> addToSetlist(Setlist s, Iterable<ScoreEntry> entries) async {
    s.items.addAll(entries.map((e) => SetlistItem.create(e.relativePath)));
    await saveSetlist(s);
  }

  /// Ein Lesezeichen (Bereich eines Stücks) als eigenen Eintrag hinzufügen.
  Future<void> addBookmarkToSetlist(Setlist s, ScoreEntry entry, String bookmark, String label) async {
    s.items.add(SetlistItem.create(entry.relativePath, bookmark: bookmark, label: label));
    await saveSetlist(s);
  }

  ScoreEntry? byPath(String path) {
    for (final s in _scores) {
      if (s.path == path) return s;
    }
    return null;
  }
}
