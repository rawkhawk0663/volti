import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/app_settings.dart';
import '../../core/library/folders.dart';
import '../../core/library/library_scanner.dart';
import '../../core/library/score_importer.dart';
import '../../core/library/score_meta.dart';
import '../../core/library/setlist.dart';
import '../../core/library/sidecar_store.dart';
import '../../core/teaching/student.dart';
import '../../core/pdf/paper.dart';
import '../../core/pdf/paper_pdf.dart';
import 'auto_backup_controller.dart';
import '../../app/l10n.dart';

/// Hält den Zustand der Bibliothek: Stücke und Setlists.
///
/// Die Noten liegen in Voltis eigenem Datenordner ([root]). Neue Stücke
/// kommen über den Import hinein.
class LibraryController extends ChangeNotifier {
  LibraryController(this.settings, {required this.root});

  final AppSettings settings;

  /// Voltis Datenordner (siehe [ScoreImporter] für den Aufbau).
  final String root;

  /// Wöchentliche automatische Sicherung dieses Geräts.
  late final autoBackup = AutoBackupController(settings: settings, root: root);

  final _scanner = const LibraryScanner();
  final _sidecars = const SidecarStore();
  late final _importer = ScoreImporter(root);
  late final _setlistStore = SetlistStore(root);
  late final _studentStore = StudentStore(root);

  List<ScoreEntry> _scores = [];

  /// Stücke der Bibliothek (ohne die Notizblätter der Setlists).
  List<ScoreEntry> get scores {
    if (!identical(_scoresOf, _scores)) {
      _scoresOf = _scores;
      _visibleScores = [
        for (final s in _scores)
          if (!s.isSheet) s,
      ];
    }
    return _visibleScores;
  }

  List<ScoreEntry>? _scoresOf;
  List<ScoreEntry> _visibleScores = const [];

  List<Setlist> _setlists = [];
  List<Setlist> get setlists => _setlists;

  /// Unterricht: Karteien der Schüler:innen (nach Name).
  List<Student> _students = [];
  List<Student> get students => _students;

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
      _students = await _studentStore.loadAll();
      await scoreFolders.load();
      await setlistFolders.load();
    } catch (e) {
      error = tr('Die Bibliothek konnte nicht gelesen werden: $e', 'The library could not be read: $e');
    }
    _loading = false;
    notifyListeners();
  }

  // ----------------------------------------------------------- Unterricht
  Student? studentById(String id) => _students.where((s) => s.id == id).firstOrNull;

  Future<Student> createStudent(String name) async {
    final s = await _studentStore.save(Student.create(name));
    _students = [..._students, s]..sort(_byName);
    notifyListeners();
    onLocalChange?.call();
    return s;
  }

  /// Kartei speichern (mit dem Stand auf der Festplatte zusammengeführt).
  /// Gibt die gespeicherte Fassung zurück; sie ersetzt die bisherige in der Liste.
  Future<Student> saveStudent(Student s) async {
    final saved = await _studentStore.save(s);
    _students = [
      for (final x in _students)
        if (x.id != s.id) x,
      saved,
    ]..sort(_byName);
    notifyListeners();
    onLocalChange?.call();
    return saved;
  }

  Future<void> deleteStudent(Student s) async {
    await _studentStore.delete(s);
    _students = _students.where((x) => x.id != s.id).toList();
    notifyListeners();
    onLocalChange?.call();
  }

  static int _byName(Student a, Student b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());

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
  void _foldersChanged() {
    notifyListeners();
    onLocalChange?.call();
  }

  /// Ordner der Bibliothek und (getrennt davon) der Setlists.
  late final scoreFolders = FolderBook(FolderStore(root), _foldersChanged);
  late final setlistFolders = FolderBook(FolderStore(root, file: FolderStore.setlistsFile), _foldersChanged);

  FolderTree get folders => scoreFolders.tree;

  /// Ordner, in dem ein Stück liegt (null = oberste Ebene).
  String? folderOf(ScoreEntry e) => folders.resolve(e.folderId);

  /// Stücke direkt in einem Ordner (ohne Unterordner).
  List<ScoreEntry> scoresIn(String? folder) => [
    for (final s in scores)
      if (folderOf(s) == folder) s,
  ];

  /// Anzahl Stücke in einem Ordner samt Unterordnern.
  int countIn(String folder) => scores.where((s) {
    final f = folderOf(s);
    return f != null && folders.isInside(f, folder);
  }).length;

  Future<ScoreFolder> createFolder(String name, {String? parent}) => scoreFolders.create(name, parent: parent);
  Future<void> renameFolder(ScoreFolder f, String name) => scoreFolders.rename(f, name);
  Future<bool> moveFolder(ScoreFolder f, String? parent) => scoreFolders.move(f, parent);
  Future<void> deleteFolder(ScoreFolder f) => scoreFolders.delete(f);
  Future<void> restoreFolder(ScoreFolder f) => scoreFolders.restore(f);

  // ---------------------------------------------- Setlists in Ordnern
  String? setlistFolderOf(Setlist s) => setlistFolders.tree.resolve(s.folder);

  List<Setlist> setlistsIn(String? folder) => [
    for (final s in _setlists)
      if (setlistFolderOf(s) == folder) s,
  ];

  int setlistCountIn(String folder) => _setlists.where((s) {
    final f = setlistFolderOf(s);
    return f != null && setlistFolders.tree.isInside(f, folder);
  }).length;

  Future<void> moveSetlists(Iterable<Setlist> lists, String? folder) async {
    for (final s in lists) {
      s.folder = folder;
      s.touch();
      await _setlistStore.save(s);
    }
    notifyListeners();
    onLocalChange?.call();
  }

  Future<void> deleteSetlists(Iterable<Setlist> lists) async {
    final ids = {for (final s in lists) s.id};
    for (final s in lists) {
      await _setlistStore.delete(s);
    }
    _setlists = _setlists.where((x) => !ids.contains(x.id)).toList();
    notifyListeners();
    onLocalChange?.call();
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

  // ------------------------------------------------------- Notizblätter
  /// Neues Notizblatt (ein A4-Blatt, leer oder mit Vorlage wie Notenlinien,
  /// z. B. für Notizen als Music Director). Es liegt wie ein Stück in
  /// `Noten/` (so wird es abgeglichen), erscheint aber nur in Setlists.
  /// Weitere Seiten kommen über „Leere Seite einfügen“ dazu (mit derselben
  /// Vorlage, gemerkt im Info-Feld `paper`).
  Future<ScoreEntry?> createSheet(String name, {Paper paper = Paper.blank}) async {
    final bytes = await buildPaperPdf(paper, title: name);
    final file = 'Notizblatt-${const Uuid().v4().substring(0, 8)}.pdf';
    final path = p.join(_importer.notesDir, file);
    await Directory(_importer.notesDir).create(recursive: true);
    await File(path).writeAsBytes(bytes, flush: true);
    final meta = ScoreMeta()
      ..set(ScoreMeta.title, name)
      ..set(ScoreMeta.sheet, true);
    if (paper != Paper.blank) meta.set(ScoreMeta.paper, paper.name);
    await _sidecars.save(path, meta: meta);
    await rescan();
    onLocalChange?.call();
    return byPath(path);
  }

  /// Eintrag [index] aus der Setlist nehmen. Ein Notizblatt wird dabei
  /// gelöscht, wenn es in keiner anderen Setlist mehr vorkommt.
  Future<void> removeFromSetlist(Setlist s, int index) async {
    final item = s.items.removeAt(index);
    await saveSetlist(s);
    final entry = byRelativePath(item.relativePath);
    if (entry == null || !entry.isSheet) return;
    final usedElsewhere = _setlists.any((x) => x.items.any((i) => i.relativePath == item.relativePath));
    if (!usedElsewhere) await deleteScores([entry]);
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
    // Nach einem Neu-Einlesen (z. B. beim Anlegen eines Notizblatts) kann [s]
    // eine alte Fassung sein: die aktuelle nehmen, sonst ginge etwas verloren.
    final target = _setlists.where((x) => x.id == s.id).firstOrNull ?? s;
    target.items.addAll(entries.map((e) => SetlistItem.create(e.relativePath)));
    await saveSetlist(target);
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

/// Ein Ordner-Baum (Bibliothek oder Setlists) samt Speichern.
class FolderBook {
  FolderBook(this.store, this._changed);
  final FolderStore store;
  final VoidCallback _changed;

  /// Alle Ordner (inkl. gelöschter, als Grabsteine für den Abgleich).
  List<ScoreFolder> _all = [];
  FolderTree tree = FolderTree(const []);

  Future<void> load() async => _set(await store.load());

  void _set(List<ScoreFolder> list) {
    _all = list;
    tree = FolderTree(list);
  }

  Future<void> _save(List<ScoreFolder> list) async {
    _set(list);
    await store.save(list);
    _changed();
  }

  Future<void> _replace(ScoreFolder f) => _save([for (final x in _all) x.id == f.id ? f : x]);

  Future<ScoreFolder> create(String name, {String? parent}) async {
    final f = ScoreFolder.create(name, parent: parent);
    await _save([..._all, f]);
    return f;
  }

  Future<void> rename(ScoreFolder f, String name) async {
    final cur = tree.byId(f.id);
    if (cur != null && name.trim().isNotEmpty) await _replace(cur.copyWith(name: name.trim()));
  }

  /// Ordner verschieben. Gibt false zurück, wenn das Ziel in ihm selbst liegt.
  Future<bool> move(ScoreFolder f, String? parent) async {
    if (parent != null && tree.isInside(parent, f.id)) return false;
    final cur = tree.byId(f.id);
    if (cur == null) return false;
    await _replace(cur.copyWith(parent: () => parent));
    return true;
  }

  /// Löscht einen Ordner. Was darin liegt, rutscht eine Ebene höher.
  Future<void> delete(ScoreFolder f) async {
    final cur = tree.byId(f.id);
    if (cur != null) await _replace(cur.copyWith(deleted: true));
  }

  /// Gelöschten Ordner zurückholen (Rückgängig).
  Future<void> restore(ScoreFolder f) async {
    final cur = tree.byId(f.id);
    if (cur != null) await _replace(cur.copyWith(deleted: false));
  }
}
