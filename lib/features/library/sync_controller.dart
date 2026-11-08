import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/app_settings.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_store.dart';
import 'library_controller.dart';

enum SyncStatus { off, idle, syncing, error }

/// Steuert den Abgleich: wann er läuft, welcher Zustand angezeigt wird.
///
/// Abgeglichen wird beim Start, alle zwei Minuten, kurz nach jeder Änderung
/// und wenn man es von Hand auslöst.
class SyncController extends ChangeNotifier {
  SyncController({required this.library, required this.settings, required this.deviceDataDir});

  final LibraryController library;
  final AppSettings settings;

  /// Gerätespezifischer Ordner (für den Stand des letzten Abgleichs).
  final String deviceDataDir;

  SyncStatus _status = SyncStatus.off;
  SyncStatus get status => _status;
  DateTime? lastSync;
  String? error;

  String? get folder => settings.syncFolder;

  Timer? _periodic;
  Timer? _debounce;
  bool _running = false;
  bool _again = false;

  File get _baseFile => File(p.join(deviceDataDir, 'sync_base.json'));

  void start() {
    library.onLocalChange = scheduleSoon;
    if (folder == null) return;
    _status = SyncStatus.idle;
    _periodic = Timer.periodic(const Duration(minutes: 2), (_) => syncNow());
    syncNow();
  }

  /// Sync-Ordner einrichten. Ist im gewählten Ordner noch keine
  /// Volti-Bibliothek, wird darin ein Unterordner "Volti" angelegt.
  Future<void> configure(String chosen) async {
    var target = chosen;
    if (!await File(p.join(chosen, SyncEngine.markerPath)).exists()) target = p.join(chosen, 'Volti');
    await SyncEngine.initializeRemote(FolderSyncStore(target));
    if (await _baseFile.exists()) await _baseFile.delete(); // neuer Ordner: nichts gilt als gelöscht
    await settings.setSyncFolder(target);
    _periodic?.cancel();
    start();
  }

  Future<void> disconnect() async {
    _periodic?.cancel();
    _debounce?.cancel();
    await settings.setSyncFolder(null);
    if (await _baseFile.exists()) await _baseFile.delete();
    _status = SyncStatus.off;
    error = null;
    notifyListeners();
  }

  /// Nach einer Änderung kurz warten (weitere Änderungen bündeln), dann abgleichen.
  void scheduleSoon() {
    if (folder == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), syncNow);
  }

  Future<void> syncNow() async {
    final f = folder;
    if (f == null) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    _status = SyncStatus.syncing;
    notifyListeners();
    try {
      final report = await SyncEngine(localRoot: library.root, remote: FolderSyncStore(f), baseFile: _baseFile).run();
      lastSync = DateTime.now();
      error = null;
      _status = SyncStatus.idle;
      if (report.changedLocally) await library.rescan();
    } catch (e) {
      error = e is SyncException ? e.message : 'Abgleich fehlgeschlagen: $e';
      _status = SyncStatus.error;
    } finally {
      _running = false;
      notifyListeners();
    }
    if (_again) {
      _again = false;
      await syncNow();
    }
  }

  @override
  void dispose() {
    _periodic?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
