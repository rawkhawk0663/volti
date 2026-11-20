import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/library/backup.dart';
import '../../app/error_log.dart';
import '../../app/open_url.dart';
import '../../app/visuals.dart';
import '../../app/window_buttons.dart';
import 'library_controller.dart';
import 'settings_dialog.dart';
import 'sync_controller.dart';
import '../../app/l10n.dart';

/// Sync, Sicherung und Einstellungen – gemeinsam für Bibliothek und Setlists.
mixin LibraryActions<T extends StatefulWidget> on State<T> {
  LibraryController get library;
  SyncController get syncController;

  /// Sync-Knopf und Zahnrad für die Kopfzeile.
  List<Widget> headerActions() => [
    SyncButton(sync: syncController, onSetup: setupSync),
    IconButton(
      tooltip: tr('Einstellungen', 'Settings'),
      icon: const Icon(Icons.settings_outlined),
      onPressed: () => showSettingsDialog(
        context,
        sync: syncController,
        onSetupSync: setupSync,
        onStopSync: stopSync,
        dataFolder: library.root,
        onOpenDataFolder: Platform.isWindows || Platform.isLinux ? library.revealDataFolder : null,
        onCreateBackup: createBackup,
        onRestoreBackup: restoreBackup,
        autoBackup: library.autoBackup,
        library: library,
      ),
    ),
    // Schliessen, Minimieren, Maximieren (statt der Windows-Titelleiste).
    const WindowButtons(),
  ];

  /// Am Computer (Datei-Fenster zum Speichern, Ordner als Sync-Ziel).
  bool get isDesktop => !Platform.isAndroid && !Platform.isIOS;

  /// Sync einrichten: Dropbox, Google Drive oder ein Ordner (z. B. Proton Drive).
  Future<void> setupSync() async {
    final choice = await showDialog<SyncKind>(
      context: context,
      builder: (c) {
        final theme = Theme.of(c);
        Widget option(SyncKind k, IconData icon, String title, String text) => ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          enabled: k.available,
          leading: Icon(icon, color: k.available ? theme.colorScheme.primary : null),
          title: Text(title),
          subtitle: Text(
            k.available ? text : tr('In dieser Version noch nicht eingerichtet.', 'Not set up in this version yet.'),
          ),
          onTap: () => Navigator.pop(c, k),
        );
        return AlertDialog(
          title: Text(tr('Sync einrichten', 'Set up sync')),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr(
                    'Volti gleicht Noten, Infos, Anmerkungen und Setlists zwischen deinen Geräten ab. '
                        'Wähle auf jedem Gerät dasselbe. Beim ersten Abgleich wird nichts gelöscht: '
                        'Die Noten beider Seiten werden zusammengelegt.',
                    'Volti syncs your music, details, notes and setlists between your devices. '
                        'Choose the same on every device. The first sync never deletes anything: '
                        'the music from both sides is combined.',
                  ),
                ),
                const SizedBox(height: 12),
                option(
                  SyncKind.dropbox,
                  Icons.cloud_outlined,
                  tr('Dropbox (empfohlen)', 'Dropbox (recommended)'),
                  tr(
                    'Volti spricht direkt mit Dropbox, am Computer und auf Android. Die Daten liegen im Ordner „Apps“ von Dropbox.',
                    'Volti talks to Dropbox directly, on the computer and on Android. The data lives in Dropbox’s “Apps” folder.',
                  ),
                ),
                // Google Drive nur, wenn es eingerichtet ist (der Besitzer nutzt Dropbox).
                if (SyncKind.gdrive.available)
                  option(
                    SyncKind.gdrive,
                    Icons.add_to_drive_outlined,
                    'Google Drive',
                    tr(
                      'Volti spricht direkt mit Google Drive. Die Daten liegen im Ordner „Volti“.',
                      'Volti talks to Google Drive directly. The data lives in the folder “Volti”.',
                    ),
                  ),
                // Ein Ordner als Ziel geht nur am Computer.
                if (SyncController.folderPossible)
                  option(
                    SyncKind.folder,
                    Icons.folder_outlined,
                    tr('Ordner (z. B. Proton Drive)', 'Folder (e.g. Proton Drive)'),
                    tr(
                      'Ein Ordner, den ein Cloud-Programm auf diesem Computer abgleicht. Nur unter Windows.',
                      'A folder that a cloud program keeps in sync on this computer. Windows only.',
                    ),
                  ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Abbrechen', 'Cancel')))],
        );
      },
    );
    if (choice == null || !mounted) return;
    if (choice == SyncKind.folder) {
      final dir = await getDirectoryPath(confirmButtonText: tr('Für Sync verwenden', 'Use for sync'));
      if (dir == null) return;
      await syncController.configure(dir);
      if (mounted) setState(() {});
      return;
    }
    // Android: Anmeldung mit Code (die Rückmeldung an das Gerät geht dort nicht).
    if (choice == SyncKind.dropbox && SyncController.prefersCode) {
      await _connectWithCode();
      return;
    }
    await _connectCloud(choice);
  }

  /// Anmeldung im Browser, solange ein Hinweis mit „Abbrechen“ steht.
  /// Bei Dropbox gibt es dort „Geht nicht? Mit Code verbinden“.
  Future<void> _connectCloud(SyncKind kind) async {
    final cancel = Completer<void>();
    var useCode = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(tr('Mit ${kind.label} verbinden', 'Connect to ${kind.label}')),
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  tr(
                    'Im Browser hat sich ${kind.label} geöffnet. Melde dich dort an und erlaube Volti den Zugriff. '
                        'Danach geht es hier von selbst weiter.',
                    '${kind.label} has opened in your browser. Sign in there and allow Volti access. '
                        'Volti continues here by itself afterwards.',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            if (kind == SyncKind.dropbox)
              TextButton(
                onPressed: () {
                  useCode = true;
                  if (!cancel.isCompleted) cancel.complete();
                },
                child: Text(tr('Geht nicht? Mit Code verbinden', 'Not working? Connect with a code')),
              ),
            TextButton(
              onPressed: () {
                if (!cancel.isCompleted) cancel.complete();
              },
              child: Text(tr('Abbrechen', 'Cancel')),
            ),
          ],
        ),
      ),
    );
    String? failed;
    try {
      await syncController.connectCloud(kind, openBrowser: openUrl, cancel: cancel.future);
    } catch (e, st) {
      if (!cancel.isCompleted) {
        failed = '$e';
        ErrorLog.record(e, st, where: 'Sync verbinden');
      }
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    await bringWindowToFront();
    if (!mounted) return;
    setState(() {});
    if (useCode) {
      await _connectWithCode();
      return;
    }
    if (cancel.isCompleted && failed == null && !syncController.configured) return;
    _connectedMessage(failed);
  }

  /// Anmeldung mit Code: Dropbox zeigt nach der Anmeldung einen Code, den man
  /// hier einfügt (Android, und am Computer als Ersatz).
  Future<void> _connectWithCode() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DropboxCodeDialog(sync: syncController),
    );
    if (!mounted) return;
    setState(() {});
    if (ok == true) _connectedMessage(null);
  }

  void _connectedMessage(String? failed) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          failed != null
              ? tr('Verbinden ging nicht: $failed', 'Connecting didn’t work: $failed')
              : tr(
                  'Verbunden: ${syncController.targetLabel}. Der erste Abgleich läuft.',
                  'Connected: ${syncController.targetLabel}. The first sync is running.',
                ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------- Sicherung
  static XTypeGroup get _zipType =>
      XTypeGroup(label: tr('Volti-Sicherung', 'Volti backup'), extensions: ['zip'], mimeTypes: ['application/zip']);

  /// Zeigt „Bitte warten“, solange [work] läuft.
  Future<R?> busy<R>(String message, Future<R> Function() work) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
    try {
      return await work();
    } catch (e) {
      if (mounted) {
        final text = e is FormatException ? e.message : '$e';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('Das ging nicht: $text', 'That didn’t work: $text'))));
      }
      return null;
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> createBackup() async {
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name = 'Volti-Sicherung-${d.year}-${two(d.month)}-${two(d.day)}.zip';
    String path;
    if (isDesktop) {
      final loc = await getSaveLocation(suggestedName: name, acceptedTypeGroups: [_zipType]);
      if (loc == null) return;
      path = loc.path.toLowerCase().endsWith('.zip') ? loc.path : '${loc.path}.zip';
    } else {
      // Android: in Voltis Dokumente-Ordner.
      final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, tr('Sicherung', 'Backup')));
      await dir.create(recursive: true);
      path = p.join(dir.path, name);
    }
    if (!mounted) return;
    final n = await busy(
      tr('Sicherung wird erstellt …', 'Creating backup …'),
      () => LibraryBackup.create(library.root, path),
    );
    if (n == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          tr(
            'Sicherung gespeichert (${n == 1 ? '1 Stück' : '$n Stücke'}):\n$path',
            'Backup saved (${n == 1 ? '1 piece' : '$n pieces'}):\n$path',
          ),
        ),
      ),
    );
  }

  Future<void> restoreBackup() async {
    final file = await openFile(acceptedTypeGroups: [_zipType], confirmButtonText: tr('Einspielen', 'Restore'));
    if (file == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Sicherung einspielen?', 'Restore backup?')),
        content: SizedBox(
          width: 460,
          child: Text(
            tr(
              'Volti nimmt alles aus der Sicherung dazu: fehlende Noten, Setlists, Ordner und Stempel. '
                  'Anmerkungen und Infos werden zusammengeführt, bei Unterschieden gilt die jüngere Änderung. '
                  'Gelöscht oder ersetzt wird nichts.',
              'Volti adds everything from the backup: missing music, setlists, folders and stamps. '
                  'Notes and details are merged; where they differ, the more recent change wins. '
                  'Nothing is deleted or replaced.',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Einspielen', 'Restore'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final work = (await getTemporaryDirectory()).path;
    if (!mounted) return;
    final report = await busy(
      tr('Sicherung wird eingespielt …', 'Restoring backup …'),
      () => LibraryBackup.restore(library.root, file.path, work),
    );
    if (report == null || !mounted) return;
    await library.rescan();
    await syncController.afterDownload?.call();
    library.onLocalChange?.call();
    if (!mounted) return;
    final added = report.downloaded, merged = report.merged;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added == 0 && merged == 0
              ? tr('Sicherung eingespielt – es war schon alles da.', 'Backup restored – everything was already there.')
              : tr(
                  'Sicherung eingespielt: $added Dateien dazugekommen, $merged zusammengeführt.',
                  'Backup restored: $added files added, $merged merged.',
                ),
        ),
      ),
    );
  }

  Future<void> stopSync() async {
    await syncController.disconnect();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            'Sync beendet. Deine Noten bleiben auf diesem Gerät und beim Sync-Ziel erhalten.',
            'Sync stopped. Your music stays on this device and at the sync target.',
          ),
        ),
      ),
    );
  }
}

/// Wolken-Symbol mit dem Sync-Zustand. Antippen gleicht sofort ab.
class SyncButton extends StatelessWidget {
  const SyncButton({super.key, required this.sync, required this.onSetup});
  final SyncController sync;
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        String two(int n) => n.toString().padLeft(2, '0');
        final last = sync.lastSync == null ? null : '${two(sync.lastSync!.hour)}:${two(sync.lastSync!.minute)}';
        final (icon, color, tip) = switch (sync.status) {
          SyncStatus.off => (
            Icons.cloud_off_outlined,
            scheme.outline,
            tr('Sync ist aus – antippen zum Einrichten', 'Sync is off – tap to set it up'),
          ),
          SyncStatus.syncing => (Icons.cloud_sync, scheme.primary, tr('Wird abgeglichen …', 'Syncing …')),
          SyncStatus.error => (Icons.cloud_off, scheme.error, sync.error ?? tr('Fehler beim Abgleich', 'Sync error')),
          SyncStatus.idle => (
            Icons.cloud_done_outlined,
            scheme.onSurfaceVariant,
            last == null
                ? tr('Sync aktiv', 'Sync active')
                : tr('Zuletzt abgeglichen um $last – antippen zum Abgleichen', 'Last synced at $last – tap to sync'),
          ),
        };
        return IconButton(
          tooltip: tip,
          icon: Icon(icon, color: color),
          onPressed: switch (sync.status) {
            SyncStatus.off => onSetup,
            SyncStatus.syncing => null,
            SyncStatus.error => () => _showError(context),
            SyncStatus.idle => sync.syncNow,
          },
        );
      },
    );
  }

  void _showError(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          sync.partialFailure
              ? tr('Nicht alles abgeglichen', 'Not everything was synced')
              : tr('Abgleich nicht möglich', 'Sync not possible'),
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sync.error ?? ''),
                if (sync.errorDetail != null) ...[
                  const SizedBox(height: 12),
                  // Genaue Meldung (zum Weitergeben, falls es weiter klemmt).
                  SelectableText(
                    tr('Genauer Grund: ${sync.errorDetail}', 'Exact reason: ${sync.errorDetail}'),
                    style: Theme.of(c).textTheme.bodySmall?.copyWith(color: Theme.of(c).colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (sync.cloudAccessDenied && Platform.isWindows)
            TextButton(
              onPressed: sync.openCloudDownloadSettings,
              child: Text(tr('Windows-Einstellung öffnen', 'Open Windows setting')),
            ),
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Schliessen', 'Close'))),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              sync.syncNow();
            },
            child: Text(tr('Nochmals versuchen', 'Try again')),
          ),
        ],
      ),
    );
  }
}

/// Mit Dropbox verbinden per Code: 1. anmelden (Browser), 2. Code kopieren,
/// 3. hier einfügen und verbinden.
class _DropboxCodeDialog extends StatefulWidget {
  const _DropboxCodeDialog({required this.sync});
  final SyncController sync;

  @override
  State<_DropboxCodeDialog> createState() => _DropboxCodeDialogState();
}

class _DropboxCodeDialogState extends State<_DropboxCodeDialog> {
  final _code = TextEditingController();
  bool _started = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Sync verbinden');
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() => _guard(() async {
    final url = widget.sync.beginCodeSignIn();
    await openUrl(url);
    if (mounted) setState(() => _started = true);
  });

  Future<void> _finish() => _guard(() async {
    await widget.sync.finishCodeSignIn(_code.text);
    if (mounted) Navigator.of(context).pop(true);
  });

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text?.trim();
    if (t != null && t.isNotEmpty) setState(() => _code.text = t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget step(int n, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text('$n', style: TextStyle(fontSize: 12, color: theme.colorScheme.onPrimaryContainer)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
    return AlertDialog(
      title: Text(tr('Mit Dropbox verbinden', 'Connect to Dropbox')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              step(
                1,
                tr(
                  '„Bei Dropbox anmelden“ tippen. Der Browser öffnet sich.',
                  'Tap “Sign in to Dropbox”. Your browser opens.',
                ),
              ),
              step(
                2,
                tr(
                  'Anmelden und Volti den Zugriff erlauben. Dropbox zeigt danach einen Code: auf „Kopieren“ tippen.',
                  'Sign in and allow Volti access. Dropbox then shows a code: tap “Copy”.',
                ),
              ),
              step(
                3,
                tr(
                  'Zurück zu Volti wechseln, „Einfügen“ und dann „Verbinden“ tippen.',
                  'Switch back to Volti, tap “Paste”, then “Connect”.',
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _start,
                  icon: const Icon(Icons.open_in_new),
                  label: Text(tr('Bei Dropbox anmelden', 'Sign in to Dropbox')),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _code,
                enabled: _started,
                decoration: InputDecoration(
                  labelText: tr('Code von Dropbox', 'Code from Dropbox'),
                  suffixIcon: IconButton(
                    tooltip: tr('Einfügen', 'Paste'),
                    icon: const Icon(Icons.content_paste),
                    onPressed: _started ? _paste : null,
                  ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _finish(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              if (_busy) ...[const SizedBox(height: 12), const LinearProgressIndicator()],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(tr('Abbrechen', 'Cancel')),
        ),
        GradientButton(
          compact: true,
          icon: const Icon(Icons.link),
          label: tr('Verbinden', 'Connect'),
          onPressed: _busy || !_started || _code.text.trim().isEmpty ? null : _finish,
        ),
      ],
    );
  }
}
