import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/app_settings.dart';
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

  List<ScoreEntry> _scores = [];
  List<ScoreEntry> get scores => _scores;

  List<Setlist> _setlists = [];
  List<Setlist> get setlists => _setlists;

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

  /// Kopiert PDFs in Voltis Datenordner.
  Future<ImportResult> importPdfs(List<String> paths) async {
    importing = true;
    notifyListeners();
    try {
      return await _importer.importFiles(paths);
    } finally {
      importing = false;
      await rescan();
      onLocalChange?.call();
    }
  }

  /// Importiert alle PDFs eines Ordners (inkl. Unterordnern).
  Future<ImportResult> importFolder(String folder) async => importPdfs(await ScoreImporter.findPdfs(folder));

  /// Löscht ein Stück endgültig aus Volti (PDF, Infos und Anmerkungen) und
  /// entfernt es aus allen Setlists.
  Future<void> deleteScore(ScoreEntry entry) async {
    for (final f in [File(entry.path), File('${entry.path}${SidecarStore.suffix}')]) {
      if (await f.exists()) await f.delete();
    }
    for (final s in _setlists) {
      final before = s.items.length;
      s.items.removeWhere((i) => i.relativePath == entry.relativePath);
      if (s.items.length != before) await saveSetlist(s);
    }
    _scores = _scores.where((e) => e.path != entry.path).toList();
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
}
