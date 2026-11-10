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

  /// Wird aufgerufen, wenn der Abgleich etwas auf dieses Gerät geholt hat.
  Future<void> Function()? afterDownload;

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

  /// Verständlicher Name einer Datei für die Meldung.
  String _describe(String rel) {
    if (rel.startsWith('.volti/setlists/')) {
      final id = p.basenameWithoutExtension(rel);
      final s = library.setlists.where((x) => x.id == id).firstOrNull;
      return s == null ? 'eine Setlist' : 'Setlist „${s.name}“';
    }
    if (rel.startsWith('.volti/stamps')) return 'eigene Stempel';
    if (rel.startsWith('.volti/')) return 'Einstellungen (${p.basename(rel)})';
    return '„${p.basename(rel).replaceAll(RegExp(r'\.volti\.json$'), '').replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '')}“';
  }

  /// Nur einzelne Dateien fehlten beim letzten Abgleich (der Rest ging).
  bool partialFailure = false;

  /// Windows hat den Zugriff auf Dateien im Cloud-Ordner verweigert.
  bool cloudAccessDenied = false;

  /// Genaue Meldung von Windows zur ersten fehlgeschlagenen Datei.
  String? errorDetail;

  /// Öffnet unter Windows die Einstellung „Automatische Dateidownloads“.
  Future<void> openCloudDownloadSettings() async {
    if (!Platform.isWindows) return;
    await Process.run('explorer.exe', ['ms-settings:privacy-automaticfiledownloads']);
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
      partialFailure = false;
      cloudAccessDenied = false;
      errorDetail = null;
      _status = SyncStatus.idle;
      if (report.failed.isNotEmpty) {
        partialFailure = true;
        cloudAccessDenied = report.cloudAccessDenied;
        final first = report.reasons.entries.firstOrNull;
        if (first != null) errorDetail = '${_describe(first.key)}: ${first.value}';
        // Das meiste ist abgeglichen; einzelne Dateien kommen beim nächsten Mal.
        final names = {for (final f in report.failed) _describe(f)}.toList();
        final list = names.take(5).join(', ') + (names.length > 5 ? ' …' : '');
        error =
            '${names.length == 1 ? 'Eine Datei konnte' : '${names.length} Dateien konnten'} diesmal nicht abgeglichen werden: '
            '$list.\n\nAlles andere ist abgeglichen. Volti versucht es beim nächsten Abgleich automatisch nochmals.\n\n'
            '${cloudAccessDenied ? 'Windows hat Volti den Zugriff auf diese Dateien im Cloud-Ordner verweigert. '
                      'Meist hilft eines davon:\n'
                      '1. In den Windows-Einstellungen unter „Automatische Dateidownloads“ Volti erlauben '
                      '(Knopf unten).\n'
                      '2. Im Explorer den Ordner „_Volti“ mit rechts anklicken → „Immer auf diesem Gerät behalten“ '
                      'und warten, bis alle Dateien ein grünes Häkchen haben.' : 'Bleibt der Fehler, prüfe bitte, ob die Dateien im Sync-Ordner vollständig heruntergeladen sind '
                      '(z. B. in Proton Drive „Immer auf diesem Gerät behalten“).'}';
        _status = SyncStatus.error;
      }
      if (report.changedLocally) {
        await library.rescan();
        await afterDownload?.call();
      }
    } catch (e) {
      partialFailure = false;
      cloudAccessDenied = '$e'.contains('errno = 395');
      errorDetail = null;
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
