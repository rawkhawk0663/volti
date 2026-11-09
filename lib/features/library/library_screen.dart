import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/library/library_filter.dart';
import '../../core/library/library_scanner.dart';
import '../../core/library/score_importer.dart';

import 'package:pdfrx/pdfrx.dart';

import '../../core/library/sidecar_store.dart';
import '../viewer/export_dialog.dart';
import '../viewer/page_export.dart';
import '../viewer/page_setup_screen.dart';
import '../viewer/tool_controller.dart';
import '../viewer/viewer_screen.dart';
import 'edit_meta_dialog.dart';
import 'library_controller.dart';
import 'open_scores.dart';
import 'score_card.dart';
import 'setlists_view.dart';
import 'sync_controller.dart';

/// Hauptbildschirm: Bibliothek mit Noten und Setlists.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.library, required this.sync});
  final LibraryController library;
  final SyncController sync;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int _tab = 0;

  LibraryController get lib => widget.library;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= 720;
        final body = _tab == 0 ? _ScoresView(library: lib, sync: widget.sync) : SetlistsView(library: lib);
        const destinations = [
          (Icons.library_music_outlined, Icons.library_music, 'Noten'),
          (Icons.queue_music_outlined, Icons.queue_music, 'Setlists'),
        ];
        if (wide) {
          return VoltiBackground(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
                child: Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _tab,
                      onDestinationSelected: (i) => setState(() => _tab = i),
                      labelType: NavigationRailLabelType.all,
                      leading: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Image.asset('assets/brand/volti_mark.png', height: 34),
                      ),
                      destinations: [
                        for (final (icon, sel, label) in destinations)
                          NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(sel), label: Text(label)),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                ),
              ),
            ),
          );
        }
        return VoltiBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(child: body),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [
                for (final (icon, sel, label) in destinations)
                  NavigationDestination(icon: Icon(icon), selectedIcon: Icon(sel), label: label),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Leere Bibliothek (z. B. beim ersten Start): Begrüssung und Import.
class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImportFiles, required this.onImportFolder});
  final VoidCallback onImportFiles;
  final VoidCallback? onImportFolder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Image.asset('assets/brand/volti_mark.png', height: 64),
                const SizedBox(width: 12),
                Image.asset('assets/brand/volti_wordmark.png', height: 48, color: dark ? Colors.white : null),
              ],
            ),
            const SizedBox(height: 28),
            Text('Willkommen!', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              'Importiere deine Noten (PDFs). Volti legt eine Kopie in seiner eigenen Bibliothek ab. '
              'Deine Originaldateien bleiben unverändert.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onImportFiles,
              icon: const Icon(Icons.file_open_outlined),
              label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('PDFs importieren')),
            ),
            if (onImportFolder != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onImportFolder,
                icon: const Icon(Icons.drive_folder_upload_outlined),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Ganzen Ordner importieren'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScoresView extends StatefulWidget {
  const _ScoresView({required this.library, required this.sync});
  final LibraryController library;
  final SyncController sync;

  @override
  State<_ScoresView> createState() => _ScoresViewState();
}

class _ScoresViewState extends State<_ScoresView> {
  String _query = '';
  ScoreSort _sort = ScoreSort.title;
  String? _genre;
  String? _tag;

  LibraryController get lib => widget.library;

  static const _sortNames = {
    ScoreSort.title: 'Titel',
    ScoreSort.composer: 'Komponist',
    ScoreSort.recentlyOpened: 'Zuletzt geöffnet',
    ScoreSort.recentlyAdded: 'Zuletzt hinzugefügt',
  };

  /// Ordner-Import gibt es auf Android nicht (dort keine Ordnerauswahl).
  bool get _canImportFolder => !Platform.isAndroid && !Platform.isIOS;

  Future<void> _importFiles() async {
    const pdf = XTypeGroup(label: 'PDF', extensions: ['pdf'], mimeTypes: ['application/pdf']);
    final files = await openFiles(acceptedTypeGroups: const [pdf], confirmButtonText: 'Importieren');
    if (files.isEmpty) return;
    _showResult(await lib.importPdfs(files.map((f) => f.path).toList()));
  }

  Future<void> _importFolder() async {
    final dir = await getDirectoryPath(confirmButtonText: 'Diesen Ordner importieren');
    if (dir == null) return;
    _showResult(await lib.importFolder(dir));
  }

  void _showResult(ImportResult r) {
    if (!mounted) return;
    final n = r.added.length;
    final parts = [
      n == 1 ? '1 Stück importiert' : '$n Stücke importiert',
      if (r.alreadyThere.isNotEmpty) '${r.alreadyThere.length} schon vorhanden',
      if (r.failed.isNotEmpty) '${r.failed.length} fehlgeschlagen',
    ];
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(parts.join(' · '))));
  }

  /// Sync über einen Ordner gibt es vorerst nur am Computer.
  bool get _canSync => _canImportFolder;

  Future<void> _setupSync() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sync einrichten'),
        content: const SizedBox(
          width: 460,
          child: Text(
            'Volti gleicht deine Noten, Infos, Anmerkungen und Setlists mit einem Ordner ab, '
            'zum Beispiel in Proton Drive. Wähle auf jedem Gerät denselben Ordner, dann sind alle '
            'Geräte auf dem gleichen Stand.\n\n'
            'Volti legt im gewählten Ordner einen Unterordner „Volti“ an. Wählst du einen Ordner, '
            'der schon eine Volti-Bibliothek enthält (vom anderen Gerät), wird diese verwendet.\n\n'
            'Beim ersten Abgleich wird nichts gelöscht: Die Noten beider Seiten werden zusammengelegt.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(c, true),
            icon: const Icon(Icons.folder_open),
            label: const Text('Ordner wählen …'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final dir = await getDirectoryPath(confirmButtonText: 'Für Sync verwenden');
    if (dir == null) return;
    await widget.sync.configure(dir);
    if (mounted) setState(() {});
  }

  Future<void> _stopSync() async {
    await widget.sync.disconnect();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sync beendet. Deine Noten bleiben auf diesem Gerät und im Sync-Ordner erhalten.')),
    );
  }

  Future<void> _delete(ScoreEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Stück löschen?'),
        content: Text(
          '„${e.title}“ wird mitsamt Infos und Anmerkungen aus Volti gelöscht '
          'und aus allen Setlists entfernt. Die Originaldatei, die du importiert hast, bleibt erhalten.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok == true) await lib.deleteScore(e);
  }

  void _open(ScoreEntry e) => openScores(context, lib, [ViewerItem(e.path, e.title)]);

  Future<void> _edit(ScoreEntry e) async {
    final changes = await showEditMetaDialog(
      context,
      entry: e,
      knownComposers: distinctValues(lib.scores, (s) => [s.composer]),
      knownGenres: distinctValues(lib.scores, (s) => [s.genre]),
      knownTags: distinctValues(lib.scores, (s) => s.tags),
    );
    if (changes != null) await lib.updateMeta(e, changes);
  }

  /// Stück als PDF (mit Anmerkungen) speichern oder drucken.
  Future<void> _export(ScoreEntry e) async {
    List<ExportPiece>? opened;
    await showExportDialog(
      context,
      title: e.title,
      load: () async => opened ??= await openExportPieces([(path: e.path, bookmark: null)]),
      release: () async {
        if (opened != null) await closeExportPieces(opened!);
      },
    );
  }

  /// Seiten anordnen und zuschneiden, ohne das Stück zu öffnen.
  Future<void> _editPages(ScoreEntry e) async {
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(e.path);
      const store = SidecarStore();
      final setup = (await store.load(e.path)).pages;
      if (!mounted) return;
      final result = await showPageSetup(context, doc: doc, setup: setup, title: e.title);
      if (result == null) return;
      await store.save(e.path, pages: result);
      lib.onLocalChange?.call();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Das ging nicht: $err')));
      }
    } finally {
      await doc?.dispose();
    }
  }

  List<PopupMenuEntry<VoidCallback>> _menu(ScoreEntry e) => [
    PopupMenuItem(
      value: () => _open(e),
      child: const ListTile(leading: Icon(Icons.open_in_new), title: Text('Öffnen')),
    ),
    PopupMenuItem(
      value: () => _edit(e),
      child: const ListTile(leading: Icon(Icons.edit_note), title: Text('Infos bearbeiten')),
    ),
    PopupMenuItem(
      value: () => _export(e),
      child: const ListTile(leading: Icon(Icons.ios_share), title: Text('Als PDF teilen …')),
    ),
    PopupMenuItem(
      value: () => _editPages(e),
      child: const ListTile(leading: Icon(Icons.auto_stories_outlined), title: Text('Seiten anordnen …')),
    ),
    PopupMenuItem(
      value: () => addToSetlistDialog(context, lib, e),
      child: const ListTile(leading: Icon(Icons.playlist_add), title: Text('Zu Setlist hinzufügen')),
    ),
    const PopupMenuDivider(),
    PopupMenuItem(
      value: () => _delete(e),
      child: const ListTile(leading: Icon(Icons.delete_outline), title: Text('Löschen …')),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final genres = distinctValues(lib.scores, (s) => [s.genre]);
    final tags = distinctValues(lib.scores, (s) => s.tags);
    if (_genre != null && !genres.contains(_genre)) _genre = null;
    if (_tag != null && !tags.contains(_tag)) _tag = null;
    final list = filterScores(
      lib.scores,
      query: _query,
      genre: _genre,
      tag: _tag,
      sort: _sort,
      lastOpened: (e) => lib.settings.lastOpened(e.path),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---------------------------------------------------------- Kopfzeile
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: SearchBar(
                  hintText: 'Titel, Komponist, Tag … suchen',
                  leading: const Icon(Icons.search),
                  elevation: const WidgetStatePropertyAll(0),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 8),
              MenuAnchor(
                menuChildren: [
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.file_open_outlined),
                    onPressed: _importFiles,
                    child: const Text('PDFs importieren …'),
                  ),
                  if (_canImportFolder)
                    MenuItemButton(
                      leadingIcon: const Icon(Icons.drive_folder_upload_outlined),
                      onPressed: _importFolder,
                      child: const Text('Ganzen Ordner importieren …'),
                    ),
                ],
                builder: (context, controller, _) => FilledButton.tonalIcon(
                  onPressed: lib.importing ? null : () => controller.isOpen ? controller.close() : controller.open(),
                  icon: const Icon(Icons.add),
                  label: const Text('Importieren'),
                ),
              ),
              IconButton(
                tooltip: 'Bibliothek neu einlesen',
                onPressed: lib.loading ? null : lib.rescan,
                icon: const Icon(Icons.refresh),
              ),
              if (_canSync) SyncButton(sync: widget.sync, onSetup: _setupSync),
              PopupMenuButton<VoidCallback>(
                tooltip: 'Einstellungen',
                icon: const Icon(Icons.settings_outlined),
                onSelected: (a) => a(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    enabled: false,
                    child: Text('Voltis Datenordner:\n${lib.root}', style: theme.textTheme.bodySmall),
                  ),
                  // Darstellung: hell, dunkel oder wie das System
                  for (final (mode, label, icon) in const [
                    (ThemeMode.system, 'Darstellung: wie das System', Icons.brightness_auto_outlined),
                    (ThemeMode.light, 'Darstellung: hell', Icons.light_mode_outlined),
                    (ThemeMode.dark, 'Darstellung: dunkel', Icons.dark_mode_outlined),
                  ])
                    PopupMenuItem(
                      value: () => ToolScope.read(context).setThemeMode(mode),
                      child: ListTile(
                        leading: Icon(icon),
                        title: Text(label),
                        trailing: ToolScope.read(context).themeMode.value == mode ? const Icon(Icons.check) : null,
                      ),
                    ),
                  const PopupMenuDivider(),
                  if (Platform.isWindows || Platform.isLinux)
                    PopupMenuItem(
                      value: lib.revealDataFolder,
                      child: const ListTile(leading: Icon(Icons.folder_open), title: Text('Datenordner öffnen')),
                    ),
                  if (_canSync) ...[
                    const PopupMenuDivider(),
                    if (widget.sync.folder == null)
                      PopupMenuItem(
                        value: _setupSync,
                        child: const ListTile(
                          leading: Icon(Icons.cloud_sync_outlined),
                          title: Text('Sync einrichten …'),
                        ),
                      )
                    else ...[
                      PopupMenuItem(
                        enabled: false,
                        child: Text('Sync-Ordner:\n${widget.sync.folder}', style: theme.textTheme.bodySmall),
                      ),
                      PopupMenuItem(
                        value: widget.sync.syncNow,
                        child: const ListTile(leading: Icon(Icons.sync), title: Text('Jetzt abgleichen')),
                      ),
                      PopupMenuItem(
                        value: _setupSync,
                        child: const ListTile(
                          leading: Icon(Icons.drive_file_move_outline),
                          title: Text('Anderen Sync-Ordner …'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _stopSync,
                        child: const ListTile(leading: Icon(Icons.cloud_off_outlined), title: Text('Sync beenden')),
                      ),
                    ],
                  ],
                ],
              ),
            ],
          ),
        ),
        // ------------------------------------------------- Sortieren / Filter
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _MenuChip<ScoreSort>(
                icon: Icons.sort,
                label: 'Sortieren: ${_sortNames[_sort]}',
                options: {for (final e in _sortNames.entries) e.key: e.value},
                onSelected: (v) => setState(() => _sort = v ?? ScoreSort.title),
              ),
              if (genres.isNotEmpty)
                _MenuChip<String>(
                  icon: Icons.category_outlined,
                  label: _genre ?? 'Alle Genres',
                  active: _genre != null,
                  options: {null: 'Alle Genres', for (final g in genres) g: g},
                  onSelected: (v) => setState(() => _genre = v),
                ),
              if (tags.isNotEmpty)
                _MenuChip<String>(
                  icon: Icons.sell_outlined,
                  label: _tag ?? 'Alle Tags',
                  active: _tag != null,
                  options: {null: 'Alle Tags', for (final t in tags) t: t},
                  onSelected: (v) => setState(() => _tag = v),
                ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    list.length == 1 ? '1 Stück' : '${list.length} Stücke',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (lib.loading || lib.importing) const LinearProgressIndicator(minHeight: 2),
        // --------------------------------------------------------------- Raster
        Expanded(child: _buildGrid(context, list)),
      ],
    );
  }

  Widget _buildGrid(BuildContext context, List<ScoreEntry> list) {
    final theme = Theme.of(context);
    if (lib.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(lib.error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: lib.rescan, child: const Text('Nochmals versuchen')),
            ],
          ),
        ),
      );
    }
    if (lib.scores.isEmpty && !lib.loading) {
      return _EmptyLibrary(onImportFiles: _importFiles, onImportFolder: _canImportFolder ? _importFolder : null);
    }
    if (list.isEmpty && !lib.loading) {
      return Center(child: Text('Keine Treffer.', style: theme.textTheme.bodyMedium));
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.58,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final e = list[i];
        return ScoreCard(key: ValueKey(e.path), entry: e, onOpen: () => _open(e), menuBuilder: (_) => _menu(e));
      },
    );
  }
}

/// Kleiner Knopf mit Auswahlmenü (für Sortierung und Filter).
class _MenuChip<T> extends StatelessWidget {
  const _MenuChip({
    required this.icon,
    required this.label,
    required this.options,
    required this.onSelected,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final Map<T?, String> options;
  final ValueChanged<T?> onSelected;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: MenuAnchor(
          menuChildren: [
            for (final e in options.entries) MenuItemButton(onPressed: () => onSelected(e.key), child: Text(e.value)),
          ],
          builder: (context, controller, _) => FilterChip(
            avatar: Icon(icon, size: 18),
            label: Text(label),
            selected: active,
            showCheckmark: false,
            onSelected: (_) => controller.isOpen ? controller.close() : controller.open(),
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
          SyncStatus.off => (Icons.cloud_off_outlined, scheme.outline, 'Sync ist aus – antippen zum Einrichten'),
          SyncStatus.syncing => (Icons.cloud_sync, scheme.primary, 'Wird abgeglichen …'),
          SyncStatus.error => (Icons.cloud_off, scheme.error, sync.error ?? 'Fehler beim Abgleich'),
          SyncStatus.idle => (
            Icons.cloud_done_outlined,
            scheme.onSurfaceVariant,
            last == null ? 'Sync aktiv' : 'Zuletzt abgeglichen um $last – antippen zum Abgleichen',
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
        title: const Text('Abgleich nicht möglich'),
        content: SizedBox(width: 460, child: Text(sync.error ?? '')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Schliessen')),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              sync.syncNow();
            },
            child: const Text('Nochmals versuchen'),
          ),
        ],
      ),
    );
  }
}
