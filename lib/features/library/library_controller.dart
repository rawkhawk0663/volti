import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/app_settings.dart';
import '../../core/library/library_scanner.dart';
import '../../core/library/score_meta.dart';
import '../../core/library/setlist.dart';
import '../../core/library/sidecar_store.dart';

/// Hält den Zustand der Bibliothek: Ordner, Stücke, Setlists.
class LibraryController extends ChangeNotifier {
  LibraryController(this.settings);

  final AppSettings settings;
  final _scanner = const LibraryScanner();
  final _sidecars = const SidecarStore();

  String? get root => settings.libraryRoot;

  List<ScoreEntry> _scores = [];
  List<ScoreEntry> get scores => _scores;

  List<Setlist> _setlists = [];
  List<Setlist> get setlists => _setlists;

  bool _loading = false;
  bool get loading => _loading;

  String? error;

  SetlistStore? get _setlistStore => root == null ? null : SetlistStore(root!);

  Future<void> init() async {
    if (root != null) await rescan();
  }

  Future<void> chooseRoot(String path) async {
    await settings.setLibraryRoot(path);
    _scores = [];
    _setlists = [];
    notifyListeners();
    await rescan();
  }

  Future<void> rescan() async {
    final r = root;
    if (r == null) return;
    _loading = true;
    error = null;
    notifyListeners();
    try {
      if (!await Directory(r).exists()) {
        error = 'Der Bibliotheksordner wurde nicht gefunden:\n$r';
      } else {
        _scores = await _scanner.scan(r);
        _setlists = await _setlistStore!.loadAll();
      }
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

  String absolutePath(String rel) => p.joinAll([root!, ...rel.split('/')]);

  /// Kopiert PDFs in den Bibliotheksordner. Gibt die Anzahl kopierter Dateien zurück.
  Future<int> importPdfs(List<String> paths) async {
    final r = root;
    if (r == null) return 0;
    var count = 0;
    for (final src in paths) {
      if (p.isWithin(r, src)) continue; // liegt schon in der Bibliothek
      var target = p.join(r, p.basename(src));
      var n = 2;
      while (await File(target).exists()) {
        target = p.join(r, '${p.basenameWithoutExtension(src)} ($n).pdf');
        n++;
      }
      await File(src).copy(target);
      // Vorhandene Anmerkungen aus dem alten Ort mitnehmen.
      final side = File('$src${SidecarStore.suffix}');
      if (await side.exists()) await side.copy('$target${SidecarStore.suffix}');
      count++;
    }
    await rescan();
    return count;
  }

  Future<void> updateMeta(ScoreEntry entry, Map<String, Object?> changes) async {
    final meta = ScoreMeta(entry.meta.fields);
    changes.forEach(meta.set);
    final saved = await _sidecars.save(entry.path, meta: meta);
    entry.meta = saved.meta;
    notifyListeners();
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
    await _setlistStore!.save(s);
    _setlists = [..._setlists, s]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    return s;
  }

  Future<void> saveSetlist(Setlist s) async {
    s.touch();
    await _setlistStore!.save(s);
    _setlists = [..._setlists]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
  }

  Future<void> deleteSetlist(Setlist s) async {
    await _setlistStore!.delete(s);
    _setlists = _setlists.where((x) => x.id != s.id).toList();
    notifyListeners();
  }

  Future<void> addToSetlist(Setlist s, Iterable<ScoreEntry> entries) async {
    s.items.addAll(entries.map((e) => SetlistItem.create(e.relativePath)));
    await saveSetlist(s);
  }
}
