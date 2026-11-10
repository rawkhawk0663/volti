import 'dart:io';

import 'package:flutter/material.dart';

import '../viewer/tool_controller.dart';
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
  });

  final ToolController tools;
  final SyncController? sync;
  final VoidCallback? onSetupSync, onStopSync, onOpenDataFolder;
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
                    if (sync != null) ..._syncSection(context, sync!),
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
