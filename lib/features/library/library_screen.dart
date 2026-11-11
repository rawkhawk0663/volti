import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/window_buttons.dart';
import '../../core/library/folders.dart';
import '../../core/library/library_filter.dart';
import '../../core/library/library_scanner.dart';
import '../../core/library/score_importer.dart';

import 'package:pdfrx/pdfrx.dart';

import '../../core/library/sidecar_store.dart';
import '../viewer/export_dialog.dart';
import '../viewer/page_export.dart';
import '../viewer/page_setup_screen.dart';
import '../viewer/viewer_screen.dart';
import 'edit_meta_dialog.dart';
import 'folder_widgets.dart';
import 'library_actions.dart';
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

  /// Nochmals auf den gewählten Punkt tippen = zurück zur Übersicht.
  final _reset = [ValueNotifier(0), ValueNotifier(0)];

  LibraryController get lib => widget.library;

  void _select(int i) {
    if (i == _tab) {
      _reset[i].value++;
    } else {
      setState(() => _tab = i);
    }
  }

  @override
  void dispose() {
    for (final r in _reset) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= 720;
        // Beide bleiben bestehen: Beim Wechsel ist man wieder am selben Ort
        // (Ordner, offene Setlist).
        final body = IndexedStack(
          index: _tab,
          children: [
            _ScoresView(library: lib, sync: widget.sync, reset: _reset[0], active: _tab == 0),
            SetlistsView(library: lib, sync: widget.sync, reset: _reset[1], active: _tab == 1),
          ],
        );
        const destinations = [
          (Icons.library_music_outlined, Icons.library_music, 'Bibliothek'),
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
                      onDestinationSelected: _select,
                      labelType: NavigationRailLabelType.all,
                      // Am Logo lässt sich das Fenster verschieben (keine Titelleiste).
                      leading: WindowDragArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          child: Image.asset('assets/brand/volti_mark.png', height: 34),
                        ),
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
              onDestinationSelected: _select,
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
  const _ScoresView({required this.library, required this.sync, required this.reset, required this.active});

  /// Gerade sichtbar? (Nur dann wirkt die Zurück-Taste hier.)
  final bool active;
  final LibraryController library;
  final SyncController sync;

  /// Meldet „zurück zur obersten Ebene“ (nochmals auf Bibliothek getippt).
  final ValueListenable<int> reset;

  @override
  State<_ScoresView> createState() => _ScoresViewState();
}

class _ScoresViewState extends State<_ScoresView> with LibraryActions {
  @override
  LibraryController get library => widget.library;
  @override
  SyncController get syncController => widget.sync;

  String _query = '';
  final _search = TextEditingController();

  /// Suche leeren (das „x“ im Suchfeld, und beim Öffnen eines gefundenen Ordners).
  void _clearSearch() => setState(() {
    _search.clear();
    _query = '';
  });

  @override
  void initState() {
    super.initState();
    widget.reset.addListener(_toTop);
  }

  /// Nochmals auf „Bibliothek“ getippt: zurück zur obersten Ebene.
  void _toTop() {
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selected.clear();
      _search.clear();
      _query = '';
      _folder = null;
      _all = false;
    });
  }

  @override
  void dispose() {
    widget.reset.removeListener(_toTop);
    _search.dispose();
    super.dispose();
  }

  ScoreSort _sort = ScoreSort.title;
  String? _genre;
  String? _tag;

  /// Offener Ordner (null = oberste Ebene) bzw. "Alle Noten".
  String? _folder;
  bool _all = false;

  /// Auswahl-Modus: mehrere Stücke ankreuzen (Pfade).
  bool _selecting = false;
  final Set<String> _selected = {};

  LibraryController get lib => widget.library;

  /// Offener Ordner – ist er inzwischen gelöscht (z. B. vom anderen Gerät),
  /// der nächste übergeordnete.
  String? get _current => _all ? null : lib.folders.resolve(_folder);

  void _openFolder(String? id, {bool all = false}) => setState(() {
    _folder = id;
    _all = all;
  });

  /// Eine Ebene nach oben.
  void _up() {
    if (_all) {
      _openFolder(null);
    } else if (_current != null) {
      _openFolder(lib.folders.parentOf(_current!));
    }
  }

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
    _showResult(await lib.importPdfs(files.map((f) => f.path).toList(), folder: _current));
  }

  Future<void> _importFolder() async {
    final dir = await getDirectoryPath(confirmButtonText: 'Diesen Ordner importieren');
    if (dir == null) return;
    _showResult(await lib.importFolder(dir, folder: _current));
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

  Future<void> _delete(ScoreEntry e) => _deleteMany([e]);

  Future<void> _deleteMany(List<ScoreEntry> list) async {
    if (list.isEmpty) return;
    final one = list.length == 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(one ? 'Stück löschen?' : '${list.length} Stücke löschen?'),
        content: SizedBox(
          width: 460,
          child: Text(
            '${one ? '„${list.first.title}“ wird' : 'Die ${list.length} Stücke werden'} mitsamt Infos und '
            'Anmerkungen aus Volti gelöscht und aus allen Setlists entfernt. '
            'Die Originaldateien, die du importiert hast, bleiben erhalten.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    await lib.deleteScores(list);
    if (mounted && _selecting) _endSelecting();
  }

  // ------------------------------------------------------------ Ordner
  String _folderName(String? id) => id == null ? 'Bibliothek' : (lib.folders.byId(id)?.name ?? 'Ordner');

  Future<void> _newFolder() async {
    final parent = _current;
    final name = await askForName(
      context,
      title: parent == null ? 'Neuer Ordner' : 'Neuer Ordner in „${_folderName(parent)}“',
      initial: '',
    );
    if (name == null) return;
    await lib.createFolder(name, parent: parent);
  }

  Future<void> _renameFolder(ScoreFolder f) async {
    final name = await askForName(context, title: 'Ordner umbenennen', initial: f.name);
    if (name != null) await lib.renameFolder(f, name);
  }

  Future<void> _moveFolder(ScoreFolder f) async {
    final to = await pickFolder(
      context,
      lib,
      title: '„${f.name}“ verschieben nach …',
      current: lib.folders.parentOf(f.id),
      exclude: f.id,
    );
    if (to == null) return;
    await lib.moveFolder(f, to.folder);
  }

  Future<void> _deleteFolder(ScoreFolder f) async {
    final n = lib.countIn(f.id);
    final parent = lib.folders.parentOf(f.id);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Ordner „${f.name}“ löschen?'),
        content: SizedBox(
          width: 460,
          child: Text(
            '${n == 0
                ? 'Der Ordner ist leer.'
                : n == 1
                ? 'Das Stück darin wird nicht gelöscht.'
                : 'Die $n Stücke darin werden nicht gelöscht.'} '
            'Was im Ordner liegt (auch Unterordner), kommt nach „${_folderName(parent)}“.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ordner löschen')),
        ],
      ),
    );
    if (ok != true) return;
    await lib.deleteFolder(f);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        persist: false,
        duration: const Duration(seconds: 6),
        content: Text('Ordner „${f.name}“ gelöscht'),
        action: SnackBarAction(label: 'Rückgängig', onPressed: () => lib.restoreFolder(f)),
      ),
    );
  }

  List<PopupMenuEntry<VoidCallback>> _folderMenu(ScoreFolder f) => [
    PopupMenuItem(
      value: () => _openFolder(f.id),
      child: const ListTile(leading: Icon(Icons.folder_open_outlined), title: Text('Öffnen')),
    ),
    PopupMenuItem(
      value: () => _renameFolder(f),
      child: const ListTile(leading: Icon(Icons.drive_file_rename_outline), title: Text('Umbenennen …')),
    ),
    PopupMenuItem(
      value: () => _moveFolder(f),
      child: const ListTile(leading: Icon(Icons.drive_file_move_outline), title: Text('Verschieben …')),
    ),
    const PopupMenuDivider(),
    PopupMenuItem(
      value: () => _deleteFolder(f),
      child: const ListTile(leading: Icon(Icons.folder_delete_outlined), title: Text('Ordner löschen …')),
    ),
  ];

  Future<void> _moveScores(List<ScoreEntry> list) async {
    if (list.isEmpty) return;
    final folders = {for (final e in list) lib.folderOf(e)};
    final to = await pickFolder(
      context,
      lib,
      title: list.length == 1 ? '„${list.first.title}“ verschieben nach …' : '${list.length} Stücke verschieben nach …',
      current: folders.length == 1 ? folders.first : '__keiner__',
    );
    if (to == null) return;
    await lib.moveScores(list, to.folder);
    if (!mounted) return;
    if (_selecting) _endSelecting();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${list.length == 1 ? '„${list.first.title}“ liegt' : '${list.length} Stücke liegen'} jetzt in „${_folderName(to.folder)}“',
        ),
      ),
    );
  }

  // ---------------------------------------------------------- Auswahl
  void _startSelecting([ScoreEntry? first]) => setState(() {
    _selecting = true;
    _selected.clear();
    if (first != null) _selected.add(first.path);
  });

  void _endSelecting() => setState(() {
    _selecting = false;
    _selected.clear();
  });

  void _toggle(ScoreEntry e) => setState(() {
    if (!_selected.remove(e.path)) _selected.add(e.path);
  });

  List<ScoreEntry> get _selectedEntries => [
    for (final e in lib.scores)
      if (_selected.contains(e.path)) e,
  ];

  Future<void> _exportMany(List<ScoreEntry> list) async {
    if (list.isEmpty) return;
    if (list.length == 1) return _export(list.first);
    List<ExportPiece>? opened;
    await showExportDialog(
      context,
      title: '${list.length} Stücke',
      load: () async =>
          opened ??= await openExportPieces([for (final e in list) (path: e.path, bookmark: null, scope: null)]),
      release: () async {
        if (opened != null) await closeExportPieces(opened!);
      },
    );
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
      load: () async => opened ??= await openExportPieces([(path: e.path, bookmark: null, scope: null)]),
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
    PopupMenuItem(
      value: () => _moveScores([e]),
      child: const ListTile(leading: Icon(Icons.drive_file_move_outline), title: Text('In Ordner verschieben …')),
    ),
    if (!_selecting)
      PopupMenuItem(
        value: () => _startSelecting(e),
        child: const ListTile(leading: Icon(Icons.checklist), title: Text('Mehrere auswählen')),
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
    final searching = _query.trim().isNotEmpty;
    final current = _current;
    final list = filterScores(
      searching || _all ? lib.scores : lib.scoresIn(current),
      query: _query,
      genre: _genre,
      tag: _tag,
      sort: _sort,
      lastOpened: (e) => lib.settings.lastOpened(e.path),
    );

    // Ordner: beim Suchen die passenden, sonst die Unterordner des offenen.
    final words = _query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final folders = _all
        ? const <ScoreFolder>[]
        : searching
        ? [
            for (final f in lib.folders.live)
              if (words.every(f.name.toLowerCase().contains)) f,
          ]
        : lib.folders.children(current);
    final showAll = !searching && !_all && current == null && lib.folders.live.isNotEmpty;

    return PopScope(
      // Zurück-Taste (Android) bzw. Esc: Auswahl beenden, Ordner nach oben.
      canPop: !widget.active || (!_selecting && !_all && current == null),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !widget.active) return;
        if (_selecting) {
          _endSelecting();
        } else {
          _up();
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---------------------------------------------------------- Kopfzeile
          if (_selecting)
            _selectionBar(list)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: SearchBar(
                      controller: _search,
                      hintText: 'Titel, Komponist, Tonart … suchen',
                      leading: const Icon(Icons.search),
                      trailing: [
                        if (_query.isNotEmpty)
                          IconButton(tooltip: 'Suche leeren', icon: const Icon(Icons.close), onPressed: _clearSearch),
                      ],
                      elevation: const WidgetStatePropertyAll(0),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: current == null ? 'Neuer Ordner' : 'Neuer Ordner in „${_folderName(current)}“',
                    onPressed: _all ? null : _newFolder,
                    icon: const Icon(Icons.create_new_folder_outlined),
                  ),
                  IconButton(
                    tooltip: 'Mehrere auswählen',
                    onPressed: lib.scores.isEmpty ? null : () => _startSelecting(),
                    icon: const Icon(Icons.checklist),
                  ),
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
                      onPressed: lib.importing
                          ? null
                          : () => controller.isOpen ? controller.close() : controller.open(),
                      icon: const Icon(Icons.add),
                      label: const Text('Importieren'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Bibliothek neu einlesen',
                    onPressed: lib.loading ? null : lib.rescan,
                    icon: const Icon(Icons.refresh),
                  ),
                  ...headerActions(),
                ],
              ),
            ),
          if ((current != null || _all) && !searching) _breadcrumbs(current),
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
          Expanded(
            child: _buildGrid(context, list, folders, showAll: showAll, searching: searching),
          ),
        ],
      ),
    );
  }

  /// Leiste im Auswahl-Modus: Anzahl und was man mit allen machen kann.
  Widget _selectionBar(List<ScoreEntry> visible) {
    final theme = Theme.of(context);
    final chosen = _selectedEntries;
    final none = chosen.isEmpty;
    final allChosen = visible.isNotEmpty && visible.every((e) => _selected.contains(e.path));
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Material(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              IconButton(tooltip: 'Auswahl beenden', onPressed: _endSelecting, icon: const Icon(Icons.close)),
              Expanded(
                child: Text(
                  none
                      ? 'Stücke antippen zum Auswählen'
                      : chosen.length == 1
                      ? '1 Stück ausgewählt'
                      : '${chosen.length} Stücke ausgewählt',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              TextButton(
                onPressed: visible.isEmpty
                    ? null
                    : () => setState(() {
                        if (allChosen) {
                          for (final e in visible) {
                            _selected.remove(e.path);
                          }
                        } else {
                          _selected.addAll(visible.map((e) => e.path));
                        }
                      }),
                child: Text(allChosen ? 'Keine' : 'Alle'),
              ),
              IconButton(
                tooltip: 'In Ordner verschieben',
                onPressed: none ? null : () => _moveScores(chosen),
                icon: const Icon(Icons.drive_file_move_outline),
              ),
              IconButton(
                tooltip: 'Zu Setlist hinzufügen',
                onPressed: none
                    ? null
                    : () async {
                        await addManyToSetlistDialog(context, lib, chosen);
                        if (mounted) _endSelecting();
                      },
                icon: const Icon(Icons.playlist_add),
              ),
              IconButton(
                tooltip: 'Als PDF teilen',
                onPressed: none ? null : () => _exportMany(chosen),
                icon: const Icon(Icons.ios_share),
              ),
              IconButton(
                tooltip: 'Löschen',
                onPressed: none ? null : () => _deleteMany(chosen),
                icon: const Icon(Icons.delete_outline),
              ),
              const WindowButtons(),
            ],
          ),
        ),
      ),
    );
  }

  /// Wo man ist: Bibliothek › Ordner › Unterordner. Jeder Teil nimmt
  /// gezogene Stücke an (mit Maus oder Stift).
  Widget _breadcrumbs(String? current) {
    final theme = Theme.of(context);
    final path = lib.folders.pathTo(current);
    Widget crumb(String? id, String label, {required bool last}) {
      final style = last
          ? theme.textTheme.titleMedium
          : theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary);
      final text = Text(label, style: style, overflow: TextOverflow.ellipsis);
      if (_all && id == '__alle__') return text;
      return FolderDropTarget(
        library: lib,
        folder: id,
        builder: (context, hovering) => Container(
          decoration: BoxDecoration(
            color: hovering ? theme.colorScheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: last
              ? Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: text)
              : InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openFolder(id),
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: text),
                ),
        ),
      );
    }

    final sep = Icon(Icons.chevron_right, size: 20, color: theme.colorScheme.outline);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
      child: Row(
        children: [
          IconButton(tooltip: 'Zurück', onPressed: _up, icon: const Icon(Icons.arrow_back)),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  children: [
                    crumb(null, 'Bibliothek', last: false),
                    if (_all) ...[sep, crumb('__alle__', 'Alle Noten', last: true)],
                    for (final (i, f) in path.indexed) ...[sep, crumb(f.id, f.name, last: i == path.length - 1)],
                  ],
                ),
              ),
            ),
          ),
          if (current != null)
            PopupMenuButton<VoidCallback>(
              tooltip: 'Ordner',
              icon: const Icon(Icons.more_vert),
              onSelected: (a) => a(),
              itemBuilder: (_) => _folderMenu(lib.folders.byId(current)!).skip(1).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid(
    BuildContext context,
    List<ScoreEntry> list,
    List<ScoreFolder> folders, {
    required bool showAll,
    required bool searching,
  }) {
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
    final current = _current;
    if (lib.scores.isEmpty && lib.folders.live.isEmpty && !lib.loading) {
      return _EmptyLibrary(onImportFiles: _importFiles, onImportFolder: _canImportFolder ? _importFolder : null);
    }
    final nothing = list.isEmpty && folders.isEmpty && !showAll && !lib.loading;
    if (nothing && (searching || _genre != null || _tag != null)) {
      return Center(child: Text('Keine Treffer.', style: theme.textTheme.bodyMedium));
    }
    // Im Ordner, bei der Suche und in "Alle Noten" steht, wo ein Stück liegt.
    final showFolder = searching || _all;
    String? folderLabel(ScoreEntry e) {
      if (!showFolder) return null;
      final f = lib.folderOf(e);
      return f == null ? null : _folderName(f);
    }

    String count(int n) => n == 1 ? '1 Stück' : '$n Stücke';
    final subs = <String, int>{};
    String folderSubtitle(ScoreFolder f) {
      final n = lib.countIn(f.id);
      final k = subs[f.id] ??= lib.folders.children(f.id).length;
      return [count(n), if (k > 0) k == 1 ? '1 Ordner' : '$k Ordner'].join(' · ');
    }

    return CustomScrollView(
      slivers: [
        if (showAll || folders.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 280,
                mainAxisExtent: 60,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              delegate: SliverChildListDelegate([
                if (showAll)
                  FolderTile(
                    library: lib,
                    icon: Icons.library_books_outlined,
                    name: 'Alle Noten',
                    subtitle: count(lib.scores.length),
                    onOpen: () => _openFolder(null, all: true),
                  ),
                for (final f in folders)
                  FolderTile(
                    key: ValueKey('folder/${f.id}'),
                    library: lib,
                    folder: f,
                    icon: Icons.folder,
                    name: f.name,
                    subtitle: folderSubtitle(f),
                    onOpen: () {
                      if (searching) _clearSearch();
                      _openFolder(f.id);
                    },
                    menuBuilder: (_) => _folderMenu(f),
                  ),
              ]),
            ),
          ),
        if (nothing && current != null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Dieser Ordner ist noch leer.\n\n'
                  'Lege Stücke hinein: im Menü eines Stücks „In Ordner verschieben“, '
                  'mit „Mehrere auswählen“ oder mit Maus und Stift hierher ziehen. '
                  'Was du importierst, solange der Ordner offen ist, landet direkt hier.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.58,
            ),
            delegate: SliverChildBuilderDelegate(childCount: list.length, (context, i) {
              final e = list[i];
              final selected = _selecting ? _selected.contains(e.path) : null;
              final card = ScoreCard(
                entry: e,
                selected: selected,
                folderName: folderLabel(e),
                onOpen: _selecting ? () => _toggle(e) : () => _open(e),
                menuBuilder: (_) => _menu(e),
              );
              // Mit Maus oder Stift auf einen Ordner ziehen (im Auswahl-Modus
              // alle ausgewählten zusammen).
              final dragged = selected == true ? _selectedEntries : [e];
              return PointerDraggable<LibraryDrag>(
                key: ValueKey(e.path),
                data: LibraryDrag(scores: dragged),
                feedback: dragFeedback(context, dragged.length == 1 ? e.title : '${dragged.length} Stücke'),
                childWhenDragging: Opacity(opacity: 0.4, child: card),
                child: card,
              );
            }),
          ),
        ),
      ],
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
