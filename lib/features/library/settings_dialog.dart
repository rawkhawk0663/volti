import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/error_log.dart';
import '../../app/updater.dart';
import '../../app/version.dart';
import '../viewer/tool_controller.dart';
import '../../core/library/auto_backup.dart';
import 'auto_backup_controller.dart';
import 'help_dialog.dart';
import 'sync_controller.dart';
import '../../app/l10n.dart';

/// Einstellungen in einem eigenen Fenster: Darstellung, Notenansicht und –
/// aus der Bibliothek – Sync und Datenordner. Änderungen gelten sofort.
Future<void> showSettingsDialog(
  BuildContext context, {
  SyncController? sync,
  VoidCallback? onSetupSync,
  VoidCallback? onStopSync,
  String? dataFolder,
  VoidCallback? onOpenDataFolder,
  VoidCallback? onCreateBackup,
  VoidCallback? onRestoreBackup,
  AutoBackupController? autoBackup,
}) {
  final tools = ToolScope.read(context);
  return showDialog<void>(
    context: context,
    builder: (c) => _SettingsDialog(
      tools: tools,
      sync: sync,
      onSetupSync: onSetupSync,
      onStopSync: onStopSync,
      dataFolder: dataFolder,
      onOpenDataFolder: onOpenDataFolder,
      onCreateBackup: onCreateBackup,
      onRestoreBackup: onRestoreBackup,
      autoBackup: autoBackup,
    ),
  );
}

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog({
    required this.tools,
    this.sync,
    this.onSetupSync,
    this.onStopSync,
    this.dataFolder,
    this.onOpenDataFolder,
    this.onCreateBackup,
    this.onRestoreBackup,
    this.autoBackup,
  });

  final ToolController tools;
  final AutoBackupController? autoBackup;
  final SyncController? sync;
  final VoidCallback? onSetupSync, onStopSync, onOpenDataFolder, onCreateBackup, onRestoreBackup;
  final String? dataFolder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: size.height - 32),
        child: ListenableBuilder(
          listenable: Listenable.merge([tools, tools.themeMode, ?sync]),
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 8, 4),
                child: Row(
                  children: [
                    Icon(Icons.settings_outlined, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(tr('Einstellungen', 'Settings'), style: theme.textTheme.titleLarge)),
                    IconButton(
                      tooltip: tr('Schliessen', 'Close'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  children: [
                    _Section(tr('Darstellung', 'Appearance')),
                    SegmentedButton<ThemeMode>(
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined),
                          label: Text(tr('Hell', 'Light')),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined),
                          label: Text(tr('Dunkel', 'Dark')),
                        ),
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: const Icon(Icons.brightness_auto_outlined),
                          label: Text(
                            Platform.isWindows
                                ? tr('Wie Windows', 'Like Windows')
                                : tr('Wie das System', 'Like the system'),
                          ),
                        ),
                      ],
                      selected: {tools.themeMode.value},
                      onSelectionChanged: (s) => tools.setThemeMode(s.first),
                    ),
                    const SizedBox(height: 16),
                    // Absichtlich zweisprachig, damit man die Sprache auch findet,
                    // wenn man die eingestellte nicht versteht.
                    Text('Sprache · Language', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    SegmentedButton<AppLanguage>(
                      segments: [
                        for (final l in AppLanguage.values)
                          ButtonSegment(value: l, icon: const Icon(Icons.translate), label: Text(l.label)),
                      ],
                      selected: {L10n.language.value},
                      onSelectionChanged: (s) => tools.setLanguage(s.first),
                    ),
                    _Section(tr('Notenansicht', 'Music view')),
                    Text(tr('Seiten nebeneinander', 'Pages side by side'), style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    SegmentedButton<PageLayout>(
                      segments: [
                        ButtonSegment(value: PageLayout.auto, label: Text(tr('Automatisch', 'Automatic'))),
                        ButtonSegment(value: PageLayout.single, label: Text(tr('Immer eine', 'Always one'))),
                        ButtonSegment(value: PageLayout.double, label: Text(tr('Immer zwei', 'Always two'))),
                      ],
                      selected: {tools.pageLayout},
                      onSelectionChanged: (s) => tools.setPageLayout(s.first),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        tr(
                          'Automatisch: im Querformat zwei Seiten, im Hochformat eine.',
                          'Automatic: two pages in landscape, one in portrait.',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('Halbe Seitenwechsel', 'Half page turns')),
                      subtitle: Text(
                        tr(
                          'Bei einer Seite: zuerst wechselt nur die obere Hälfte.',
                          'With one page: only the top half changes first.',
                        ),
                      ),
                      value: tools.halfTurns,
                      onChanged: tools.setHalfTurns,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('Mit dem Stift sofort zeichnen', 'Draw with the pen right away')),
                      subtitle: Text(
                        tr(
                          'Auch in der Spielansicht, ohne zuerst „Bearbeiten“.',
                          'Also while playing, without tapping “Edit” first.',
                        ),
                      ),
                      value: tools.instantPen,
                      onChanged: tools.setInstantPen,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        tr('Beim Bearbeiten mit dem Finger blättern', 'Turn pages with a finger while editing'),
                      ),
                      subtitle: Text(
                        tr(
                          'Mit einem Finger zügig nach links oder rechts wischen. '
                              'Eine aufliegende Hand blättert nicht, ebenso wenig, solange der Stift in der Nähe ist.',
                          'Swipe quickly left or right with one finger. '
                              'A resting hand does not turn pages, and neither does anything while the pen is nearby.',
                        ),
                      ),
                      value: tools.swipeWhileEditing,
                      onChanged: tools.setSwipeWhileEditing,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('Werkzeugleiste links', 'Toolbar on the left')),
                      subtitle: Text(
                        tr(
                          'Aus: am rechten Rand (z. B. für Linkshänder).',
                          'Off: on the right edge (e.g. for left-handers).',
                        ),
                      ),
                      value: tools.paletteLeft,
                      onChanged: (_) => tools.togglePaletteSide(),
                    ),
                    if (onCreateBackup != null) ...[
                      _Section(tr('Sicherung', 'Backup')),
                      Text(
                        tr(
                          'Alle Noten mit Infos und Anmerkungen, Setlists, Ordnern, eigenen Stempeln und '
                              'Stift-Vorlagen in einer einzigen Datei. Beim Einspielen wird nichts gelöscht oder '
                              'überschrieben: Was fehlt, kommt dazu, Anmerkungen werden zusammengeführt.',
                          'All your music with details and notes, setlists, folders, your own stamps and '
                              'pen presets in a single file. Restoring never deletes or '
                              'overwrites anything: whatever is missing is added, and notes are merged.',
                        ),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () {
                              Navigator.pop(context);
                              onCreateBackup!();
                            },
                            icon: const Icon(Icons.save_alt),
                            label: Text(tr('Sicherung erstellen …', 'Create backup …')),
                          ),
                          if (onRestoreBackup != null)
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                onRestoreBackup!();
                              },
                              icon: const Icon(Icons.restore),
                              label: Text(tr('Sicherung einspielen …', 'Restore backup …')),
                            ),
                        ],
                      ),
                      if (autoBackup != null) ...[const SizedBox(height: 12), AutoBackupSection(autoBackup!)],
                    ],
                    if (sync != null) ..._syncSection(context, sync!),
                    _Section(tr('Über Volti', 'About Volti')),
                    Text(
                      tr(
                        'Version $voltiVersion',
                        'Version ${voltiVersion == 'Testversion' ? 'test build' : voltiVersion}',
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    const UpdateSection(),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => showHelpDialog(context),
                          icon: const Icon(Icons.help_outline),
                          label: Text(tr('Kurzanleitung', 'Quick guide')),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => showErrorLogDialog(context),
                          icon: const Icon(Icons.bug_report_outlined),
                          label: Text(tr('Fehlerprotokoll', 'Error log')),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => showVoltiLicenses(context),
                          icon: const Icon(Icons.gavel_outlined),
                          label: Text(tr('Lizenzen', 'Licences')),
                        ),
                      ],
                    ),
                    if (dataFolder != null) ...[
                      _Section(tr('Datenordner', 'Data folder')),
                      Text(
                        tr(
                          'Hier liegen deine importierten Noten, Infos und Anmerkungen:',
                          'Your imported music, details and notes are stored here:',
                        ),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      SelectableText(dataFolder!, style: theme.textTheme.bodySmall),
                      if (onOpenDataFolder != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: onOpenDataFolder,
                            icon: const Icon(Icons.folder_open),
                            label: Text(tr('Datenordner öffnen', 'Open data folder')),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _syncSection(BuildContext context, SyncController sync) {
    final theme = Theme.of(context);
    void close(VoidCallback? f) {
      Navigator.pop(context);
      f?.call();
    }

    String two(int n) => n.toString().padLeft(2, '0');
    final last = sync.lastSync;
    final status = switch (sync.status) {
      SyncStatus.off => tr('Aus', 'Off'),
      SyncStatus.syncing => tr('Wird gerade abgeglichen …', 'Syncing …'),
      SyncStatus.error => sync.error ?? tr('Fehler beim Abgleich', 'Sync error'),
      SyncStatus.idle =>
        last == null
            ? tr('Aktiv', 'Active')
            : tr(
                'Aktiv, zuletzt abgeglichen um ${two(last.hour)}:${two(last.minute)}',
                'Active, last synced at ${two(last.hour)}:${two(last.minute)}',
              ),
    };
    return [
      _Section(tr('Sync', 'Sync')),
      Text(status, style: theme.textTheme.bodyMedium),
      if (sync.folder != null) ...[
        const SizedBox(height: 4),
        SelectableText(
          tr('Sync-Ordner: ${sync.folder}', 'Sync folder: ${sync.folder}'),
          style: theme.textTheme.bodySmall,
        ),
      ],
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (sync.folder == null)
            FilledButton.icon(
              onPressed: () => close(onSetupSync),
              icon: const Icon(Icons.cloud_sync_outlined),
              label: Text(tr('Sync einrichten …', 'Set up sync …')),
            )
          else ...[
            FilledButton.tonalIcon(
              onPressed: sync.status == SyncStatus.syncing ? null : sync.syncNow,
              icon: const Icon(Icons.sync),
              label: Text(tr('Jetzt abgleichen', 'Sync now')),
            ),
            OutlinedButton.icon(
              onPressed: () => close(onSetupSync),
              icon: const Icon(Icons.drive_file_move_outline),
              label: Text(tr('Anderer Ordner …', 'Other folder …')),
            ),
            OutlinedButton.icon(
              onPressed: () => close(onStopSync),
              icon: const Icon(Icons.cloud_off_outlined),
              label: Text(tr('Sync beenden', 'Stop sync')),
            ),
          ],
        ],
      ),
    ];
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary, letterSpacing: 1.1),
      ),
    );
  }
}

/// „Nach Updates suchen“ und – unter Windows – gleich installieren.
class UpdateSection extends StatefulWidget {
  const UpdateSection({super.key});

  @override
  State<UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<UpdateSection> {
  bool _busy = false;
  String? _message;
  UpdateInfo? _found;
  double? _progress;

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _message = null;
      _found = null;
    });
    try {
      final u = await Updater.latest();
      if (!mounted) return;
      setState(() {
        if (u == null) {
          _message = tr('Noch keine Versionen zum Herunterladen gefunden.', 'No versions available for download yet.');
        } else if (Updater.isNewer(u)) {
          _found = u;
        } else {
          _message = tr('Du hast die neueste Version.', 'You have the latest version.');
        }
      });
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _message = tr('Keine Verbindung zu GitHub. Bist du online?', 'No connection to GitHub. Are you online?'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _install(UpdateInfo u) async {
    if (!await Updater.canSelfInstall()) {
      await Updater.openPage(u);
      if (mounted) {
        setState(
          () => _message = tr(
            'Die Download-Seite ist im Browser geöffnet.',
            'The download page has opened in your browser.',
          ),
        );
      }
      return;
    }
    setState(() => _progress = 0);
    try {
      await Updater.installWindows(
        u,
        onProgress: (v) {
          if (mounted) setState(() => _progress = v);
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _message = tr('Das Update ging nicht: $e', 'The update didn’t work: $e');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final u = _found;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (u == null)
          OutlinedButton.icon(
            onPressed: _busy ? null : _check,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.system_update_alt),
            label: Text(tr('Nach Updates suchen', 'Check for updates')),
          )
        else ...[
          Text(
            tr('Neue Version ${u.tag} ist bereit.', 'New version ${u.tag} is ready.'),
            style: theme.textTheme.titleSmall,
          ),
          if (u.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                u.notes.split('\n').first,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 8),
          if (_progress != null) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 4),
            Text(
              _progress! < 1
                  ? tr('Wird heruntergeladen …', 'Downloading …')
                  : tr(
                      'Volti schliesst sich kurz und startet in der neuen Version neu …',
                      'Volti closes briefly and restarts in the new version …',
                    ),
              style: theme.textTheme.bodySmall,
            ),
          ] else
            FilledButton.icon(
              onPressed: () => Platform.isWindows ? _install(u) : Updater.openPage(u),
              icon: const Icon(Icons.download),
              label: Text(
                Platform.isWindows
                    ? tr('Jetzt installieren und neu starten', 'Install now and restart')
                    : tr('Herunterladen', 'Download'),
              ),
            ),
          if (!Platform.isWindows)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SelectableText(u.page.toString(), style: theme.textTheme.bodySmall),
            ),
        ],
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_message!, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}

/// Beim Start einmal leise nachschauen; gibt es eine neue Version, erscheint
/// unten ein Hinweis mit „Installieren“. Ohne Verbindung passiert nichts.
Future<void> checkForUpdateQuietly(BuildContext context) async {
  if (Updater.currentNumber == 0) return; // Testversion
  UpdateInfo? u;
  try {
    u = await Updater.latest();
  } catch (_) {
    return;
  }
  if (u == null || !Updater.isNewer(u) || !context.mounted) return;
  final found = u;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      persist: false,
      duration: const Duration(seconds: 10),
      content: Text(tr('Neue Version ${found.tag} ist bereit.', 'New version ${found.tag} is ready.')),
      action: SnackBarAction(
        label: Platform.isWindows ? tr('Installieren', 'Install') : tr('Herunterladen', 'Download'),
        onPressed: () => _installWithProgress(context, found),
      ),
    ),
  );
}

Future<void> _installWithProgress(BuildContext context, UpdateInfo u) async {
  if (!await Updater.canSelfInstall()) {
    await Updater.openPage(u);
    return;
  }
  if (!context.mounted) return;
  final progress = ValueNotifier<double>(0);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: Text(tr('Update auf ${u.tag}', 'Update to ${u.tag}')),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (context, v, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: v),
            const SizedBox(height: 8),
            Text(
              v < 0.9
                  ? tr('Wird heruntergeladen …', 'Downloading …')
                  : v < 1
                  ? tr('Wird eingerichtet …', 'Setting up …')
                  : tr('Volti startet in der neuen Version neu …', 'Volti is restarting in the new version …'),
            ),
          ],
        ),
      ),
    ),
  );
  try {
    await Updater.installWindows(u, onProgress: (v) => progress.value = v);
  } catch (e, st) {
    ErrorLog.record(e, st, where: 'Update');
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('Das Update ging nicht: $e', 'The update didn’t work: $e'))));
    }
  }
}

/// Nach einem Update: kurz melden, ob es geklappt hat.
Future<void> reportLastUpdate(BuildContext context) async {
  final r = await Updater.lastUpdateResult();
  if (r == null || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      persist: false,
      duration: Duration(seconds: r.ok ? 5 : 12),
      content: Text(r.message),
      action: r.ok
          ? null
          : SnackBarAction(
              label: tr('Download-Seite', 'Download page'),
              onPressed: () => Updater.openPage(
                UpdateInfo(tag: '', number: 0, page: Uri.parse('https://github.com/${Updater.repo}/releases/latest')),
              ),
            ),
    ),
  );
}

String _when(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}, ${two(d.hour)}:${two(d.minute)}';
}

/// Wöchentliche automatische Sicherung: an/aus, Ordner, jetzt sichern.
class AutoBackupSection extends StatefulWidget {
  const AutoBackupSection(this.backup, {super.key});
  final AutoBackupController backup;

  @override
  State<AutoBackupSection> createState() => _AutoBackupSectionState();
}

class _AutoBackupSectionState extends State<AutoBackupSection> {
  String? _folder;

  @override
  void initState() {
    super.initState();
    _loadFolder();
  }

  Future<void> _loadFolder() async {
    final f = await widget.backup.folder();
    if (mounted) setState(() => _folder = f);
  }

  Future<void> _chooseFolder() async {
    final dir = await getDirectoryPath(
      confirmButtonText: tr('Hier sichern', 'Back up here'),
      initialDirectory: _folder,
    );
    if (dir == null) return;
    await widget.backup.setFolder(dir);
    await _loadFolder();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return ListenableBuilder(
      listenable: widget.backup,
      builder: (context, _) {
        final b = widget.backup;
        final last = b.last;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Jede Woche automatisch sichern', 'Back up automatically every week')),
              subtitle: Text(
                b.running
                    ? tr('Sicherung läuft gerade …', 'Backup in progress …')
                    : b.lastError != null
                    ? tr(
                        'Die letzte Sicherung ging nicht: ${b.lastError}',
                        'The last backup didn’t work: ${b.lastError}',
                      )
                    : last == null
                    ? tr('Noch keine automatische Sicherung.', 'No automatic backup yet.')
                    : tr(
                        'Zuletzt: ${_when(last)}. Die letzten ${AutoBackup.keep} bleiben liegen.',
                        'Last: ${_when(last)}. The latest ${AutoBackup.keep} are kept.',
                      ),
              ),
              value: b.enabled,
              onChanged: b.setEnabled,
            ),
            if (b.enabled) ...[
              if (_folder != null) SelectableText(tr('Ordner: $_folder', 'Folder: $_folder'), style: small),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: b.running ? null : b.runNow,
                    icon: const Icon(Icons.backup_outlined),
                    label: Text(tr('Jetzt sichern', 'Back up now')),
                  ),
                  if (!Platform.isAndroid)
                    OutlinedButton.icon(
                      onPressed: _chooseFolder,
                      icon: const Icon(Icons.folder_open),
                      label: Text(tr('Anderer Ordner …', 'Other folder …')),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Fehlerprotokoll ansehen, kopieren (z. B. um es weiterzuschicken) oder leeren.
Future<void> showErrorLogDialog(BuildContext context) async {
  var text = await ErrorLog.read();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        final theme = Theme.of(c);
        final empty = text.trim().isEmpty;
        return AlertDialog(
          title: Text(tr('Fehlerprotokoll', 'Error log')),
          content: SizedBox(
            width: 560,
            child: empty
                ? Text(tr('Es sind keine Fehler aufgezeichnet. 👍', 'No errors recorded. 👍'))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        tr(
                          'Wenn etwas nicht klappt: „Kopieren“ antippen und den Text weiterschicken. '
                              'Er enthält keine Noten und keine persönlichen Inhalte, nur die technischen Fehlermeldungen.',
                          'If something doesn’t work: tap “Copy” and send the text on. '
                              'It contains no music and no personal content, only the technical error messages.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SingleChildScrollView(
                            reverse: true,
                            child: SelectableText(
                              text,
                              style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'VoltiMono'),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            if (!empty) ...[
              TextButton(
                onPressed: () async {
                  await ErrorLog.clear();
                  setState(() => text = '');
                },
                child: Text(tr('Leeren', 'Clear')),
              ),
              FilledButton.tonalIcon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (c.mounted) {
                    ScaffoldMessenger.of(c)
                        .showSnackBar(SnackBar(content: Text(tr('Fehlerprotokoll kopiert.', 'Error log copied.'))));
                  }
                },
                icon: const Icon(Icons.copy),
                label: Text(tr('Kopieren', 'Copy')),
              ),
            ],
            TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Schliessen', 'Close'))),
          ],
        );
      },
    ),
  );
}

/// Lizenzen der verwendeten Bausteine (Schriften, PDF-Technik, Flutter …).
void showVoltiLicenses(BuildContext context) {
  showLicensePage(
    context: context,
    applicationName: 'Volti',
    applicationVersion: voltiVersion,
    applicationIcon: Padding(
      padding: const EdgeInsets.all(8),
      child: Image.asset('assets/brand/volti_mark.png', height: 48),
    ),
    applicationLegalese: tr(
      'Notenzeichen: Bravura (Steinberg, SIL Open Font License). '
          'Schriften: Roboto, Roboto Mono und Noto Serif (SIL Open Font License).',
      'Music symbols: Bravura (Steinberg, SIL Open Font License). '
          'Fonts: Roboto, Roboto Mono and Noto Serif (SIL Open Font License).',
    ),
  );
}
