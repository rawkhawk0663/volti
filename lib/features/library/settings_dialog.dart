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
                    Expanded(child: Text('Einstellungen', style: theme.textTheme.titleLarge)),
                    IconButton(
                      tooltip: 'Schliessen',
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
                    const _Section('Darstellung'),
                    SegmentedButton<ThemeMode>(
                      segments: [
                        const ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined),
                          label: Text('Hell'),
                        ),
                        const ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined),
                          label: Text('Dunkel'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: const Icon(Icons.brightness_auto_outlined),
                          label: Text(Platform.isWindows ? 'Wie Windows' : 'Wie das System'),
                        ),
                      ],
                      selected: {tools.themeMode.value},
                      onSelectionChanged: (s) => tools.setThemeMode(s.first),
                    ),
                    const _Section('Notenansicht'),
                    Text('Seiten nebeneinander', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    SegmentedButton<PageLayout>(
                      segments: const [
                        ButtonSegment(value: PageLayout.auto, label: Text('Automatisch')),
                        ButtonSegment(value: PageLayout.single, label: Text('Immer eine')),
                        ButtonSegment(value: PageLayout.double, label: Text('Immer zwei')),
                      ],
                      selected: {tools.pageLayout},
                      onSelectionChanged: (s) => tools.setPageLayout(s.first),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Automatisch: im Querformat zwei Seiten, im Hochformat eine.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Halbe Seitenwechsel'),
                      subtitle: const Text('Bei einer Seite: zuerst wechselt nur die obere Hälfte.'),
                      value: tools.halfTurns,
                      onChanged: tools.setHalfTurns,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mit dem Stift sofort zeichnen'),
                      subtitle: const Text('Auch in der Spielansicht, ohne zuerst „Bearbeiten“.'),
                      value: tools.instantPen,
                      onChanged: tools.setInstantPen,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Werkzeugleiste links'),
                      subtitle: const Text('Aus: am rechten Rand (z. B. für Linkshänder).'),
                      value: tools.paletteLeft,
                      onChanged: (_) => tools.togglePaletteSide(),
                    ),
                    if (onCreateBackup != null) ...[
                      const _Section('Sicherung'),
                      Text(
                        'Alle Noten mit Infos und Anmerkungen, Setlists, Ordnern, eigenen Stempeln und '
                        'Stift-Vorlagen in einer einzigen Datei. Beim Einspielen wird nichts gelöscht oder '
                        'überschrieben: Was fehlt, kommt dazu, Anmerkungen werden zusammengeführt.',
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
                            label: const Text('Sicherung erstellen …'),
                          ),
                          if (onRestoreBackup != null)
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                onRestoreBackup!();
                              },
                              icon: const Icon(Icons.restore),
                              label: const Text('Sicherung einspielen …'),
                            ),
                        ],
                      ),
                      if (autoBackup != null) ...[const SizedBox(height: 12), AutoBackupSection(autoBackup!)],
                    ],
                    if (sync != null) ..._syncSection(context, sync!),
                    const _Section('Über Volti'),
                    Text('Version $voltiVersion', style: theme.textTheme.bodyMedium),
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
                          label: const Text('Kurzanleitung'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => showErrorLogDialog(context),
                          icon: const Icon(Icons.bug_report_outlined),
                          label: const Text('Fehlerprotokoll'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => showVoltiLicenses(context),
                          icon: const Icon(Icons.gavel_outlined),
                          label: const Text('Lizenzen'),
                        ),
                      ],
                    ),
                    if (dataFolder != null) ...[
                      const _Section('Datenordner'),
                      Text(
                        'Hier liegen deine importierten Noten, Infos und Anmerkungen:',
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
                            label: const Text('Datenordner öffnen'),
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
      SyncStatus.off => 'Aus',
      SyncStatus.syncing => 'Wird gerade abgeglichen …',
      SyncStatus.error => sync.error ?? 'Fehler beim Abgleich',
      SyncStatus.idle => last == null ? 'Aktiv' : 'Aktiv, zuletzt abgeglichen um ${two(last.hour)}:${two(last.minute)}',
    };
    return [
      const _Section('Sync'),
      Text(status, style: theme.textTheme.bodyMedium),
      if (sync.folder != null) ...[
        const SizedBox(height: 4),
        SelectableText('Sync-Ordner: ${sync.folder}', style: theme.textTheme.bodySmall),
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
              label: const Text('Sync einrichten …'),
            )
          else ...[
            FilledButton.tonalIcon(
              onPressed: sync.status == SyncStatus.syncing ? null : sync.syncNow,
              icon: const Icon(Icons.sync),
              label: const Text('Jetzt abgleichen'),
            ),
            OutlinedButton.icon(
              onPressed: () => close(onSetupSync),
              icon: const Icon(Icons.drive_file_move_outline),
              label: const Text('Anderer Ordner …'),
            ),
            OutlinedButton.icon(
              onPressed: () => close(onStopSync),
              icon: const Icon(Icons.cloud_off_outlined),
              label: const Text('Sync beenden'),
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
          _message = 'Noch keine Versionen zum Herunterladen gefunden.';
        } else if (Updater.isNewer(u)) {
          _found = u;
        } else {
          _message = 'Du hast die neueste Version.';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _message = 'Keine Verbindung zu GitHub. Bist du online?');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _install(UpdateInfo u) async {
    if (!await Updater.canSelfInstall()) {
      await Updater.openPage(u);
      if (mounted) {
        setState(() => _message = 'Die Download-Seite ist im Browser geöffnet.');
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
          _message = 'Das Update ging nicht: $e';
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
            label: const Text('Nach Updates suchen'),
          )
        else ...[
          Text('Neue Version ${u.tag} ist bereit.', style: theme.textTheme.titleSmall),
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
                  ? 'Wird heruntergeladen …'
                  : 'Volti schliesst sich kurz und startet in der neuen Version neu …',
              style: theme.textTheme.bodySmall,
            ),
          ] else
            FilledButton.icon(
              onPressed: () => Platform.isWindows ? _install(u) : Updater.openPage(u),
              icon: const Icon(Icons.download),
              label: Text(Platform.isWindows ? 'Jetzt installieren und neu starten' : 'Herunterladen'),
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
      content: Text('Neue Version ${found.tag} ist bereit.'),
      action: SnackBarAction(
        label: Platform.isWindows ? 'Installieren' : 'Herunterladen',
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
      title: Text('Update auf ${u.tag}'),
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
                  ? 'Wird heruntergeladen …'
                  : v < 1
                  ? 'Wird eingerichtet …'
                  : 'Volti startet in der neuen Version neu …',
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Das Update ging nicht: $e')));
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
              label: 'Download-Seite',
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
    final dir = await getDirectoryPath(confirmButtonText: 'Hier sichern', initialDirectory: _folder);
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
              title: const Text('Jede Woche automatisch sichern'),
              subtitle: Text(
                b.running
                    ? 'Sicherung läuft gerade …'
                    : b.lastError != null
                    ? 'Die letzte Sicherung ging nicht: ${b.lastError}'
                    : last == null
                    ? 'Noch keine automatische Sicherung.'
                    : 'Zuletzt: ${_when(last)}. Die letzten ${AutoBackup.keep} bleiben liegen.',
              ),
              value: b.enabled,
              onChanged: b.setEnabled,
            ),
            if (b.enabled) ...[
              if (_folder != null) SelectableText('Ordner: $_folder', style: small),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: b.running ? null : b.runNow,
                    icon: const Icon(Icons.backup_outlined),
                    label: const Text('Jetzt sichern'),
                  ),
                  if (!Platform.isAndroid)
                    OutlinedButton.icon(
                      onPressed: _chooseFolder,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Anderer Ordner …'),
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
          title: const Text('Fehlerprotokoll'),
          content: SizedBox(
            width: 560,
            child: empty
                ? const Text('Es sind keine Fehler aufgezeichnet. 👍')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Wenn etwas nicht klappt: „Kopieren“ antippen und den Text weiterschicken. '
                        'Er enthält keine Noten und keine persönlichen Inhalte, nur die technischen Fehlermeldungen.',
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
                child: const Text('Leeren'),
              ),
              FilledButton.tonalIcon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (c.mounted) {
                    ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Fehlerprotokoll kopiert.')));
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Kopieren'),
              ),
            ],
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Schliessen')),
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
    applicationLegalese:
        'Notenzeichen: Bravura (Steinberg, SIL Open Font License). '
        'Schriften: Roboto, Roboto Mono und Noto Serif (SIL Open Font License).',
  );
}
