import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/library/backup.dart';
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
    if (canSync) SyncButton(sync: syncController, onSetup: setupSync),
    IconButton(
      tooltip: tr('Einstellungen', 'Settings'),
      icon: const Icon(Icons.settings_outlined),
      onPressed: () => showSettingsDialog(
        context,
        sync: canSync ? syncController : null,
        onSetupSync: setupSync,
        onStopSync: stopSync,
        dataFolder: library.root,
        onOpenDataFolder: Platform.isWindows || Platform.isLinux ? library.revealDataFolder : null,
        onCreateBackup: createBackup,
        onRestoreBackup: restoreBackup,
        autoBackup: library.autoBackup,
      ),
    ),
    // Schliessen, Minimieren, Maximieren (statt der Windows-Titelleiste).
    const WindowButtons(),
  ];

  /// Sync über einen Ordner gibt es vorerst nur am Computer.
  bool get canSync => !Platform.isAndroid && !Platform.isIOS;

  Future<void> setupSync() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Sync einrichten', 'Set up sync')),
        content: SizedBox(
          width: 460,
          child: Text(
            tr(
              'Volti gleicht deine Noten, Infos, Anmerkungen und Setlists mit einem Ordner ab, '
                  'zum Beispiel in Proton Drive. Wähle auf jedem Gerät denselben Ordner, dann sind alle '
                  'Geräte auf dem gleichen Stand.\n\n'
                  'Volti legt im gewählten Ordner einen Unterordner „Volti“ an. Wählst du einen Ordner, '
                  'der schon eine Volti-Bibliothek enthält (vom anderen Gerät), wird diese verwendet.\n\n'
                  'Beim ersten Abgleich wird nichts gelöscht: Die Noten beider Seiten werden zusammengelegt.',
              'Volti syncs your music, details, notes and setlists with a folder, '
                  'for example in Proton Drive. Choose the same folder on every device, and all '
                  'devices stay up to date.\n\n'
                  'Volti creates a subfolder “Volti” in the chosen folder. If you choose a folder '
                  'that already contains a Volti library (from another device), that one is used.\n\n'
                  'The first sync never deletes anything: the music from both sides is combined.',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton.icon(
            onPressed: () => Navigator.pop(c, true),
            icon: const Icon(Icons.folder_open),
            label: Text(tr('Ordner wählen …', 'Choose folder …')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final dir = await getDirectoryPath(confirmButtonText: tr('Für Sync verwenden', 'Use for sync'));
    if (dir == null) return;
    await syncController.configure(dir);
    if (mounted) setState(() {});
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
    if (canSync) {
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
            'Sync beendet. Deine Noten bleiben auf diesem Gerät und im Sync-Ordner erhalten.',
            'Sync stopped. Your music stays on this device and in the sync folder.',
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
