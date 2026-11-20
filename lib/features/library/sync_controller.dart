import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../app/error_log.dart';
import '../../core/app_settings.dart';
import '../../core/sync/cloud_auth.dart';
import '../../core/sync/cloud_store.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_store.dart';
import 'library_controller.dart';
import '../../app/l10n.dart';

enum SyncStatus { off, idle, syncing, error }

/// Womit abgeglichen wird.
enum SyncKind {
  /// Ein Ordner, den ein Cloud-Programm abgleicht (z. B. Proton Drive).
  folder,
  dropbox,
  gdrive;

  String get label => switch (this) {
    SyncKind.folder => tr('Ordner', 'Folder'),
    SyncKind.dropbox => 'Dropbox',
    SyncKind.gdrive => 'Google Drive',
  };

  /// Sind die Schlüssel für diesen Dienst in dieser Version eingebaut?
  bool get available => switch (this) {
    SyncKind.folder => true,
    SyncKind.dropbox => dropboxAppKey.isNotEmpty,
    SyncKind.gdrive => googleClientId.isNotEmpty && googleClientSecret.isNotEmpty,
  };
}

/// Steuert den Abgleich: wann er läuft, welcher Zustand angezeigt wird.
///
/// Abgeglichen wird beim Start, alle zwei Minuten, 4 Sekunden nach jeder
/// Änderung, wenn Volti wieder in den Vordergrund kommt, und von Hand.
class SyncController extends ChangeNotifier with WidgetsBindingObserver {
  SyncController({required this.library, required this.settings, required this.deviceDataDir});

  final LibraryController library;
  final AppSettings settings;

  /// Gerätespezifischer Ordner (für den Stand des letzten Abgleichs).
  final String deviceDataDir;

  SyncStatus _status = SyncStatus.off;
  SyncStatus get status => _status;
  DateTime? lastSync;
  String? error;

  /// Womit abgeglichen wird (null = Sync aus).
  SyncKind? get kind {
    switch (settings.text('syncKind')) {
      case 'dropbox' when settings.text('dropboxToken') != null:
        return SyncKind.dropbox;
      case 'gdrive' when settings.text('gdriveToken') != null:
        return SyncKind.gdrive;
    }
    return settings.syncFolder != null ? SyncKind.folder : null;
  }

  bool get configured => kind != null;

  /// Sync-Ordner (nur beim Abgleich über einen Ordner).
  String? get folder => kind == SyncKind.folder ? settings.syncFolder : null;

  /// Womit verbunden (für die Anzeige), z. B. „Dropbox · Anna (anna@…)“.
  String? get targetLabel => switch (kind) {
    null => null,
    SyncKind.folder => settings.syncFolder,
    final k => [k.label, ?settings.text('cloudAccount')].join(' · '),
  };

  /// Verbindung zum Cloud-Dienst, über mehrere Abgleiche behalten (der
  /// Zwischenspeicher der Infos bleibt so warm).
  SyncStore? _cloud;
  SyncKind? _cloudKind;

  SyncStore? _store() {
    final k = kind;
    switch (k) {
      case null:
        return null;
      case SyncKind.folder:
        return FolderSyncStore(settings.syncFolder!);
      case SyncKind.dropbox || SyncKind.gdrive:
        if (_cloud != null && _cloudKind == k) return _cloud;
        _cloudKind = k;
        return _cloud = CloudSyncStore(_api(k, _auth(k)), cacheDir: p.join(deviceDataDir, 'sync-cache', k.name));
    }
  }

  OAuthClient _auth(SyncKind k) {
    final key = '${k.name}Token';
    Future<void> save(String t) => settings.setText(key, t);
    return k == SyncKind.dropbox
        ? OAuthClient.dropbox(refreshToken: settings.text(key), onRefreshToken: save)
        : OAuthClient.google(refreshToken: settings.text(key), onRefreshToken: save);
  }

  CloudApi _api(SyncKind k, OAuthClient auth) => k == SyncKind.dropbox
      ? DropboxApi(auth)
      : GoogleDriveApi(auth, rootId: settings.text('gdriveRoot'), onRoot: (id) => settings.setText('gdriveRoot', id));

  /// Wird aufgerufen, wenn der Abgleich etwas auf dieses Gerät geholt hat.
  Future<void> Function()? afterDownload;

  Timer? _periodic;
  Timer? _debounce;
  bool _running = false;
  bool _again = false;

  /// Stand des letzten Abgleichs – pro Ziel eine eigene Datei, damit ein
  /// Wechsel des Ziels nie etwas als „gelöscht“ erscheinen lässt.
  File _baseFor(SyncKind? k) =>
      File(p.join(deviceDataDir, k == null || k == SyncKind.folder ? 'sync_base.json' : 'sync_base_${k.name}.json'));

  bool _observing = false;

  /// Unter Android geht die Rückmeldung an das Gerät nicht, dort mit Code.
  static bool get prefersCode => Platform.isAndroid || Platform.isIOS;

  /// Ein Ordner als Ziel geht nur am Computer.
  static bool get folderPossible => !Platform.isAndroid && !Platform.isIOS;

  void start() {
    library.onLocalChange = scheduleSoon;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    if (!configured) return;
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
    await _forgetTarget();
    await settings.setSyncFolder(target);
    await settings.setText('syncKind', SyncKind.folder.name);
    final base = _baseFor(SyncKind.folder);
    if (await base.exists()) await base.delete(); // neuer Ordner: nichts gilt als gelöscht
    _periodic?.cancel();
    start();
  }

  /// Wieder im Vordergrund (z. B. nach dem Wechsel zu einer anderen App):
  /// gleich abgleichen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && configured) syncNow();
  }

  void _requireAvailable(SyncKind k) {
    if (!k.available) {
      throw CloudAuthException(
        tr(
          'In dieser Version ist ${k.label} noch nicht eingerichtet.',
          '${k.label} is not set up in this version yet.',
        ),
      );
    }
  }

  /// Mit Dropbox oder Google Drive verbinden: Anmeldung im Browser
  /// ([openBrowser]), die Antwort kommt von selbst zurück (am Computer).
  /// [cancel] bricht ab.
  Future<void> connectCloud(SyncKind k, {required Future<void> Function(Uri) openBrowser, Future<void>? cancel}) async {
    _requireAvailable(k);
    final auth = k == SyncKind.dropbox ? OAuthClient.dropbox() : OAuthClient.google();
    await auth.signIn(openBrowser, cancel: cancel);
    await _connected(k, auth);
  }

  /// Anmeldung mit Code (Dropbox), Schritt 1: Adresse zum Öffnen im Browser.
  Uri beginCodeSignIn() {
    _requireAvailable(SyncKind.dropbox);
    final auth = OAuthClient.dropbox();
    _pending = auth;
    return auth.codeSignInUrl();
  }

  OAuthClient? _pending;

  /// Schritt 2: den von Dropbox gezeigten Code einlösen und verbinden.
  Future<void> finishCodeSignIn(String code) async {
    final auth = _pending;
    if (auth == null) {
      throw CloudAuthException(
        tr('Bitte zuerst „Bei Dropbox anmelden“ tippen.', 'Please tap “Sign in to Dropbox” first.'),
      );
    }
    await auth.finishCodeSignIn(code);
    _pending = null;
    await _connected(SyncKind.dropbox, auth);
  }

  /// Nach der Anmeldung: Volti beim Dienst einrichten, Zugang merken, abgleichen.
  Future<void> _connected(SyncKind k, OAuthClient auth) async {
    final key = '${k.name}Token';
    final api = _api(k, auth);
    // Google: den Ordner „Volti“ neu suchen (anderes Konto möglich).
    if (api is GoogleDriveApi) {
      api.rootId = null;
      await settings.removeText('gdriveRoot');
    }
    final store = CloudSyncStore(api, cacheDir: p.join(deviceDataDir, 'sync-cache', k.name));
    await SyncEngine.initializeRemote(store);
    String? account;
    try {
      account = api is DropboxApi ? await api.accountName() : await (api as GoogleDriveApi).accountName();
    } catch (_) {}
    await _forgetTarget();
    await settings.setText(key, auth.refreshToken!);
    await settings.setText('syncKind', k.name);
    if (account != null && account.isNotEmpty) await settings.setText('cloudAccount', account);
    final base = _baseFor(k);
    if (await base.exists()) await base.delete(); // neues Ziel: nichts gilt als gelöscht
    _cloud = store;
    _cloudKind = k;
    _periodic?.cancel();
    start();
  }

  /// Bisheriges Ziel vergessen (Anmeldungen, Zwischenspeicher, Stand).
  Future<void> _forgetTarget() async {
    _cloud = null;
    _cloudKind = null;
    for (final t in ['syncKind', 'dropboxToken', 'gdriveToken', 'gdriveRoot', 'cloudAccount']) {
      await settings.removeText(t);
    }
    await settings.setSyncFolder(null);
    for (final k in SyncKind.values) {
      final b = _baseFor(k);
      if (await b.exists()) await b.delete();
    }
    try {
      final cache = Directory(p.join(deviceDataDir, 'sync-cache'));
      if (await cache.exists()) await cache.delete(recursive: true);
    } catch (_) {}
  }

  Future<void> disconnect() async {
    _periodic?.cancel();
    _debounce?.cancel();
    await _forgetTarget();
    _status = SyncStatus.off;
    error = null;
    notifyListeners();
  }

  /// Nach einer Änderung kurz warten (weitere Änderungen bündeln), dann abgleichen.
  void scheduleSoon() {
    if (!configured) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), syncNow);
  }

  /// Verständlicher Name einer Datei für die Meldung.
  String _describe(String rel) {
    if (rel.startsWith('.volti/setlists/')) {
      final id = p.basenameWithoutExtension(rel);
      final s = library.setlists.where((x) => x.id == id).firstOrNull;
      return s == null ? tr('eine Setlist', 'a setlist') : tr('Setlist „${s.name}“', 'setlist “${s.name}”');
    }
    if (rel.startsWith('.volti/stamps')) return tr('eigene Stempel', 'own stamps');
    if (rel.startsWith('.volti/')) return tr('Einstellungen (${p.basename(rel)})', 'settings (${p.basename(rel)})');
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
    final store = _store();
    if (store == null) return;
    final k = kind;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    _status = SyncStatus.syncing;
    notifyListeners();
    try {
      final report = await SyncEngine(
        localRoot: library.root,
        remote: store,
        baseFile: _baseFor(k),
        unreachableMessage: k == SyncKind.folder
            ? null
            : tr(
                'Volti findet seine Bibliothek bei ${k!.label} nicht mehr. Bitte Sync neu einrichten.',
                'Volti can no longer find its library at ${k.label}. Please set up sync again.',
              ),
      ).run();
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
        ErrorLog.record(
          'Nicht abgeglichen: ${report.reasons.entries.map((e) => '${e.key}: ${e.value}').join('\n')}',
          null,
          where: 'Sync',
        );
        // Das meiste ist abgeglichen; einzelne Dateien kommen beim nächsten Mal.
        final names = {for (final f in report.failed) _describe(f)}.toList();
        final list = names.take(5).join(', ') + (names.length > 5 ? ' …' : '');
        error = tr(
          '${names.length == 1 ? 'Eine Datei konnte' : '${names.length} Dateien konnten'} diesmal nicht abgeglichen werden: '
              '$list.\n\nAlles andere ist abgeglichen. Volti versucht es beim nächsten Abgleich automatisch nochmals.\n\n'
              '${cloudAccessDenied ? 'Windows hat Volti den Zugriff auf diese Dateien im Cloud-Ordner verweigert. '
                        'Meist hilft eines davon:\n'
                        '1. In den Windows-Einstellungen unter „Automatische Dateidownloads“ Volti erlauben '
                        '(Knopf unten).\n'
                        '2. Im Explorer den Ordner „_Volti“ mit rechts anklicken → „Immer auf diesem Gerät behalten“ '
                        'und warten, bis alle Dateien ein grünes Häkchen haben.' : 'Bleibt der Fehler, prüfe bitte, ob die Dateien im Sync-Ordner vollständig heruntergeladen sind '
                        '(z. B. in Proton Drive „Immer auf diesem Gerät behalten“).'}',
          '${names.length == 1 ? 'One file' : '${names.length} files'} could not be synced this time: '
              '$list.\n\nEverything else is synced. Volti will try again automatically at the next sync.\n\n'
              '${cloudAccessDenied ? 'Windows denied Volti access to these files in the cloud folder. '
                        'Usually one of these helps:\n'
                        '1. In the Windows settings under “Automatic file downloads”, allow Volti '
                        '(button below).\n'
                        '2. In Explorer, right-click the folder “_Volti” → “Always keep on this device” '
                        'and wait until all files have a green tick.' : 'If the error persists, please check whether the files in the sync folder are fully downloaded '
                        '(e.g. in Proton Drive “Always keep on this device”).'}',
        );
        _status = SyncStatus.error;
      }
      if (report.changedLocally) {
        await library.rescan();
        await afterDownload?.call();
      }
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Sync');
      partialFailure = false;
      cloudAccessDenied = '$e'.contains('errno = 395');
      errorDetail = null;
      error = e is SyncException ? e.message : tr('Abgleich fehlgeschlagen: $e', 'Sync failed: $e');
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
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _periodic?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
