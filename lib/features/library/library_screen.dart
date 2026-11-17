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
import '../teaching/teaching_view.dart';
import '../viewer/tool_controller.dart';
import '../viewer/viewer_screen.dart';
import 'edit_meta_dialog.dart';
import 'folder_widgets.dart';
import 'help_dialog.dart';
import 'library_actions.dart';
import 'library_controller.dart';
import 'open_scores.dart';
import 'score_card.dart';
import 'setlists_view.dart';
import 'settings_dialog.dart';
import 'sync_controller.dart';
import '../../app/l10n.dart';

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
  final _reset = [ValueNotifier(0), ValueNotifier(0), ValueNotifier(0)];

  LibraryController get lib => widget.library;

  @override
  void initState() {
    super.initState();
    // Nach einem Update melden, ob es geklappt hat.
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (mounted) reportLastUpdate(context);
    });
    // Einmal beim Start nach einer neuen Version schauen (leise).
    Future<void>.delayed(const Duration(seconds: 6), () {
      if (mounted) checkForUpdateQuietly(context);
    });
    // Beim ersten Start die Kurzanleitung zeigen.
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (mounted) showHelpOnFirstStart(context, lib.settings);
    });
    // Unterricht: an Geburtstage von Schüler:innen erinnern (einmal pro Tag).
    Future<void>.delayed(const Duration(seconds: 3), _remindBirthdays);
  }

  Future<void> _remindBirthdays() async {
    if (!mounted || !ToolScope.read(context).teaching) return;
    final now = DateTime.now();
    final today = '${now.year}-${now.month}-${now.day}';
    if (lib.settings.text('birthdayReminder') == today) return;
    final list = upcomingBirthdays(lib.students, now, days: 0);
    if (list.isEmpty) return;
    await lib.settings.setText('birthdayReminder', today);
    if (!mounted) return;
    final names = list.map((b) => tr('${b.student.name} (${b.age})', '${b.student.name} (${b.age})')).join(', ');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: Row(
          children: [
            const Icon(Icons.cake_outlined, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(tr('Heute hat Geburtstag: $names 🎉', 'Birthday today: $names 🎉'))),
          ],
        ),
        action: SnackBarAction(label: tr('Unterricht', 'Teaching'), onPressed: () => _select(2)),
      ),
    );
  }

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
    final tools = ToolScope.read(context);
    return ListenableBuilder(
      listenable: Listenable.merge([lib, tools]),
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= 720;
        // Unterricht nur, wenn unter ⚙ eingeschaltet.
        final teaching = tools.teaching;
        if (!teaching && _tab == 2) _tab = 0;
        // Beide bleiben bestehen: Beim Wechsel ist man wieder am selben Ort
        // (Ordner, offene Setlist).
        final body = IndexedStack(
          index: _tab,
          children: [
            _ScoresView(library: lib, sync: widget.sync, reset: _reset[0], active: _tab == 0),
            SetlistsView(library: lib, sync: widget.sync, reset: _reset[1], active: _tab == 1),
            if (teaching)
              TeachingView(library: lib, sync: widget.sync, reset: _reset[2], active: _tab == 2)
            else
              const SizedBox.shrink(),
          ],
        );
        final destinations = [
          (Icons.library_music_outlined, Icons.library_music, tr('Bibliothek', 'Library')),
          (Icons.queue_music_outlined, Icons.queue_music, tr('Setlists', 'Setlists')),
          if (teaching) (Icons.school_outlined, Icons.school, tr('Unterricht', 'Teaching')),
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
            Text(tr('Willkommen!', 'Welcome!'), style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              tr(
                'Importiere deine Noten (PDFs). Volti legt eine Kopie in seiner eigenen Bibliothek ab. '
                    'Deine Originaldateien bleiben unverändert.',
                'Import your sheet music (PDFs). Volti keeps a copy in its own library. '
                    'Your original files stay untouched.',
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onImportFiles,
              icon: const Icon(Icons.file_open_outlined),
              label: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(tr('PDFs importieren', 'Import PDFs')),
              ),
            ),
            if (onImportFolder != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onImportFolder,
                icon: const Icon(Icons.drive_folder_upload_outlined),
                label: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(tr('Ganzen Ordner importieren', 'Import a whole folder')),
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

  static Map<ScoreSort, String> get _sortNames => {
    ScoreSort.title: tr('Titel', 'Title'),
    ScoreSort.composer: tr('Komponist', 'Composer'),
    ScoreSort.recentlyOpened: tr('Zuletzt geöffnet', 'Recently opened'),
    ScoreSort.recentlyAdded: tr('Zuletzt hinzugefügt', 'Recently added'),
  };

  /// Ordner-Import gibt es auf Android nicht (dort keine Ordnerauswahl).
  bool get _canImportFolder => !Platform.isAndroid && !Platform.isIOS;

  Future<void> _importFiles() async {
    const pdf = XTypeGroup(label: 'PDF', extensions: ['pdf'], mimeTypes: ['application/pdf']);
    final files = await openFiles(acceptedTypeGroups: const [pdf], confirmButtonText: tr('Importieren', 'Import'));
    if (files.isEmpty) return;
    _showResult(await lib.importPdfs(files.map((f) => f.path).toList(), folder: _current));
  }

  Future<void> _importFolder() async {
    final dir = await getDirectoryPath(confirmButtonText: tr('Diesen Ordner importieren', 'Import this folder'));
    if (dir == null) return;
    _showResult(await lib.importFolder(dir, folder: _current));
  }

  void _showResult(ImportResult r) {
    if (!mounted) return;
    final n = r.added.length;
    final parts = [
      n == 1 ? tr('1 Stück importiert', '1 piece imported') : tr('$n Stücke importiert', '$n pieces imported'),
      if (r.alreadyThere.isNotEmpty)
        tr('${r.alreadyThere.length} schon vorhanden', '${r.alreadyThere.length} already there'),
      if (r.failed.isNotEmpty) tr('${r.failed.length} fehlgeschlagen', '${r.failed.length} failed'),
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
        title: Text(
          one
              ? tr('Stück löschen?', 'Delete piece?')
              : tr('${list.length} Stücke löschen?', 'Delete ${list.length} pieces?'),
        ),
        content: SizedBox(
          width: 460,
          child: Text(
            tr(
              '${one ? '„${list.first.title}“ wird' : 'Die ${list.length} Stücke werden'} mitsamt Infos und '
                  'Anmerkungen aus Volti gelöscht und aus allen Setlists entfernt. '
                  'Die Originaldateien, die du importiert hast, bleiben erhalten.',
              '${one ? '“${list.first.title}” will be' : 'The ${list.length} pieces will be'} deleted from Volti together with their details and '
                  'notes, and removed from all setlists. '
                  'The original files you imported are kept.',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Löschen', 'Delete'))),
        ],
      ),
    );
    if (ok != true) return;
    await lib.deleteScores(list);
    if (mounted && _selecting) _endSelecting();
  }

  // ------------------------------------------------------------ Ordner
  String _folderName(String? id) =>
      id == null ? tr('Bibliothek', 'Library') : (lib.folders.byId(id)?.name ?? tr('Ordner', 'Folders'));

  Future<void> _newFolder() async {
    final parent = _current;
    final name = await askForName(
      context,
      title: parent == null
          ? tr('Neuer Ordner', 'New folder')
          : tr('Neuer Ordner in „${_folderName(parent)}“', 'New folder in “${_folderName(parent)}”'),
      initial: '',
    );
    if (name == null) return;
    await lib.createFolder(name, parent: parent);
  }

  Future<void> _renameFolder(ScoreFolder f) async {
    final name = await askForName(context, title: tr('Ordner umbenennen', 'Rename folder'), initial: f.name);
    if (name != null) await lib.renameFolder(f, name);
  }

  Future<void> _moveFolder(ScoreFolder f) async {
    final to = await pickFolder(
      context,
      lib,
      title: tr('„${f.name}“ verschieben nach …', 'Move “${f.name}” to …'),
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
        title: Text(tr('Ordner „${f.name}“ löschen?', 'Delete folder “${f.name}”?')),
        content: SizedBox(
          width: 460,
          child: Text(
            tr(
              '${n == 0
                      ? 'Der Ordner ist leer.'
                      : n == 1
                      ? 'Das Stück darin wird nicht gelöscht.'
                      : 'Die $n Stücke darin werden nicht gelöscht.'} '
                  'Was im Ordner liegt (auch Unterordner), kommt nach „${_folderName(parent)}“.',
              '${n == 0
                      ? 'The folder is empty.'
                      : n == 1
                      ? 'The piece inside will not be deleted.'
                      : 'The $n pieces inside will not be deleted.'} '
                  'Everything in the folder (including subfolders) moves to “${_folderName(parent)}”.',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Ordner löschen', 'Delete folder'))),
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
        content: Text(tr('Ordner „${f.name}“ gelöscht', 'Folder “${f.name}” deleted')),
        action: SnackBarAction(label: tr('Rückgängig', 'Undo'), onPressed: () => lib.restoreFolder(f)),
      ),
    );
  }

  List<PopupMenuEntry<VoidCallback>> _folderMenu(ScoreFolder f) => [
    PopupMenuItem(
      value: () => _openFolder(f.id),
      child: ListTile(leading: Icon(Icons.folder_open_outlined), title: Text(tr('Öffnen', 'Open'))),
    ),
    PopupMenuItem(
      value: () => _renameFolder(f),
      child: ListTile(leading: Icon(Icons.drive_file_rename_outline), title: Text(tr('Umbenennen …', 'Rename …'))),
    ),
    PopupMenuItem(
      value: () => _moveFolder(f),
      child: ListTile(leading: Icon(Icons.drive_file_move_outline), title: Text(tr('Verschieben …', 'Move …'))),
    ),
    const PopupMenuDivider(),
    PopupMenuItem(
      value: () => _deleteFolder(f),
      child: ListTile(
        leading: Icon(Icons.folder_delete_outlined),
        title: Text(tr('Ordner löschen …', 'Delete folder …')),
      ),
    ),
  ];

  Future<void> _moveScores(List<ScoreEntry> list) async {
    if (list.isEmpty) return;
    final folders = {for (final e in list) lib.folderOf(e)};
    final to = await pickFolder(
      context,
      lib,
      title: list.length == 1
          ? tr('„${list.first.title}“ verschieben nach …', 'Move “${list.first.title}” to …')
          : tr('${list.length} Stücke verschieben nach …', 'Move ${list.length} pieces to …'),
      current: folders.length == 1 ? folders.first : '__keiner__',
    );
    if (to == null) return;
    await lib.moveScores(list, to.folder);
    if (!mounted) return;
    if (_selecting) _endSelecting();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            '${list.length == 1 ? '„${list.first.title}“ liegt' : '${list.length} Stücke liegen'} jetzt in „${_folderName(to.folder)}“',
            '${list.length == 1 ? '“${list.first.title}” is' : '${list.length} pieces are'} now in “${_folderName(to.folder)}”',
          ),
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
      title: tr('${list.length} Stücke', '${list.length} pieces'),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('Das ging nicht: $err', 'That didn’t work: $err'))));
      }
    } finally {
      await doc?.dispose();
    }
  }

  List<PopupMenuEntry<VoidCallback>> _menu(ScoreEntry e) => [
    PopupMenuItem(
      value: () => _open(e),
      child: ListTile(leading: Icon(Icons.open_in_new), title: Text(tr('Öffnen', 'Open'))),
    ),
    PopupMenuItem(
      value: () => _edit(e),
      child: ListTile(leading: Icon(Icons.edit_note), title: Text(tr('Infos bearbeiten', 'Edit details'))),
    ),
    PopupMenuItem(
      value: () => _export(e),
      child: ListTile(leading: Icon(Icons.ios_share), title: Text(tr('Als PDF teilen …', 'Share as PDF …'))),
    ),
    PopupMenuItem(
      value: () => _editPages(e),
      child: ListTile(
        leading: Icon(Icons.auto_stories_outlined),
        title: Text(tr('Seiten anordnen …', 'Arrange pages …')),
      ),
    ),
    PopupMenuItem(
      value: () => addToSetlistDialog(context, lib, e),
      child: ListTile(leading: Icon(Icons.playlist_add), title: Text(tr('Zu Setlist hinzufügen', 'Add to setlist'))),
    ),
    PopupMenuItem(
      value: () => _moveScores([e]),
      child: ListTile(
        leading: Icon(Icons.drive_file_move_outline),
        title: Text(tr('In Ordner verschieben …', 'Move to folder …')),
      ),
    ),
    if (!_selecting)
      PopupMenuItem(
        value: () => _startSelecting(e),
        child: ListTile(leading: Icon(Icons.checklist), title: Text(tr('Mehrere auswählen', 'Select several'))),
      ),
    const PopupMenuDivider(),
    PopupMenuItem(
      value: () => _delete(e),
      child: ListTile(leading: Icon(Icons.delete_outline), title: Text(tr('Löschen …', 'Delete …'))),
    ),
  ];

  /// Importieren (unten rechts): einzelne PDFs oder einen ganzen Ordner.
  Widget _importButton() {
    return MenuAnchor(
      alignmentOffset: const Offset(0, 8),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.file_open_outlined),
          onPressed: _importFiles,
          child: Text(tr('PDFs importieren …', 'Import PDFs …')),
        ),
        if (_canImportFolder)
          MenuItemButton(
            leadingIcon: const Icon(Icons.drive_folder_upload_outlined),
            onPressed: _importFolder,
            child: Text(tr('Ganzen Ordner importieren …', 'Import a whole folder …')),
          ),
      ],
      builder: (context, controller, _) => FloatingActionButton.extended(
        heroTag: 'import',
        onPressed: lib.importing ? null : () => controller.isOpen ? controller.close() : controller.open(),
        icon: lib.importing
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add),
        label: Text(lib.importing ? tr('Wird importiert …', 'Importing …') : tr('Importieren', 'Import')),
      ),
    );
  }

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
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // Importieren unten rechts, wie „Neue Setlist“ bei den Setlists. Nicht
        // beim Auswählen und nicht in der leeren Bibliothek (dort stehen die
        // grossen Import-Knöpfe in der Mitte).
        floatingActionButton: _selecting || (lib.scores.isEmpty && lib.folders.live.isEmpty && !lib.loading)
            ? null
            : _importButton(),
        body: Column(
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
                        hintText: tr('Titel, Komponist, Tonart … suchen', 'Search title, composer, key …'),
                        leading: const Icon(Icons.search),
                        trailing: [
                          if (_query.isNotEmpty)
                            IconButton(
                              tooltip: tr('Suche leeren', 'Clear search'),
                              icon: const Icon(Icons.close),
                              onPressed: _clearSearch,
                            ),
                        ],
                        elevation: const WidgetStatePropertyAll(0),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Ganz links, damit Bibliothek und Setlists sonst gleich aufgebaut sind.
                    IconButton(
                      tooltip: tr('Bibliothek neu einlesen', 'Reload library'),
                      onPressed: lib.loading ? null : lib.rescan,
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      tooltip: current == null
                          ? tr('Neuer Ordner', 'New folder')
                          : tr('Neuer Ordner in „${_folderName(current)}“', 'New folder in “${_folderName(current)}”'),
                      onPressed: _all ? null : _newFolder,
                      icon: const Icon(Icons.create_new_folder_outlined),
                    ),
                    IconButton(
                      tooltip: tr('Mehrere auswählen', 'Select several'),
                      onPressed: lib.scores.isEmpty ? null : () => _startSelecting(),
                      icon: const Icon(Icons.checklist),
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
                    label: tr('Sortieren: ${_sortNames[_sort]}', 'Sort: ${_sortNames[_sort]}'),
                    options: {for (final e in _sortNames.entries) e.key: e.value},
                    onSelected: (v) => setState(() => _sort = v ?? ScoreSort.title),
                  ),
                  if (genres.isNotEmpty)
                    _MenuChip<String>(
                      icon: Icons.category_outlined,
                      label: _genre ?? tr('Alle Genres', 'All genres'),
                      active: _genre != null,
                      options: {null: tr('Alle Genres', 'All genres'), for (final g in genres) g: g},
                      onSelected: (v) => setState(() => _genre = v),
                    ),
                  if (tags.isNotEmpty)
                    _MenuChip<String>(
                      icon: Icons.sell_outlined,
                      label: _tag ?? tr('Alle Tags', 'All tags'),
                      active: _tag != null,
                      options: {null: tr('Alle Tags', 'All tags'), for (final t in tags) t: t},
                      onSelected: (v) => setState(() => _tag = v),
                    ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        list.length == 1
                            ? tr('1 Stück', '1 piece')
                            : tr('${list.length} Stücke', '${list.length} pieces'),
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
              IconButton(
                tooltip: tr('Auswahl beenden', 'Done selecting'),
                onPressed: _endSelecting,
                icon: const Icon(Icons.close),
              ),
              Expanded(
                child: Text(
                  none
                      ? tr('Stücke antippen zum Auswählen', 'Tap pieces to select them')
                      : chosen.length == 1
                      ? tr('1 Stück ausgewählt', '1 piece selected')
                      : tr('${chosen.length} Stücke ausgewählt', '${chosen.length} pieces selected'),
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
                child: Text(allChosen ? tr('Keine', 'None') : tr('Alle', 'All')),
              ),
              IconButton(
                tooltip: tr('In Ordner verschieben', 'Move to folder'),
                onPressed: none ? null : () => _moveScores(chosen),
                icon: const Icon(Icons.drive_file_move_outline),
              ),
              IconButton(
                tooltip: tr('Zu Setlist hinzufügen', 'Add to setlist'),
                onPressed: none
                    ? null
                    : () async {
                        await addManyToSetlistDialog(context, lib, chosen);
                        if (mounted) _endSelecting();
                      },
                icon: const Icon(Icons.playlist_add),
              ),
              IconButton(
                tooltip: tr('Als PDF teilen', 'Share as PDF'),
                onPressed: none ? null : () => _exportMany(chosen),
                icon: const Icon(Icons.ios_share),
              ),
              IconButton(
                tooltip: tr('Löschen', 'Delete'),
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
          IconButton(tooltip: tr('Zurück', 'Back'), onPressed: _up, icon: const Icon(Icons.arrow_back)),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  children: [
                    crumb(null, tr('Bibliothek', 'Library'), last: false),
                    if (_all) ...[sep, crumb('__alle__', tr('Alle Noten', 'All music'), last: true)],
                    for (final (i, f) in path.indexed) ...[sep, crumb(f.id, f.name, last: i == path.length - 1)],
                  ],
                ),
              ),
            ),
          ),
          if (current != null)
            PopupMenuButton<VoidCallback>(
              tooltip: tr('Ordner', 'Folders'),
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
              FilledButton(onPressed: lib.rescan, child: Text(tr('Nochmals versuchen', 'Try again'))),
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
      return Center(child: Text(tr('Keine Treffer.', 'No matches.'), style: theme.textTheme.bodyMedium));
    }
    // Im Ordner, bei der Suche und in "Alle Noten" steht, wo ein Stück liegt.
    final showFolder = searching || _all;
    String? folderLabel(ScoreEntry e) {
      if (!showFolder) return null;
      final f = lib.folderOf(e);
      return f == null ? null : _folderName(f);
    }

    String count(int n) => n == 1 ? tr('1 Stück', '1 piece') : tr('$n Stücke', '$n pieces');
    final subs = <String, int>{};
    String folderSubtitle(ScoreFolder f) {
      final n = lib.countIn(f.id);
      final k = subs[f.id] ??= lib.folders.children(f.id).length;
      return [count(n), if (k > 0) k == 1 ? tr('1 Ordner', '1 folder') : tr('$k Ordner', '$k folders')].join(' · ');
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
                    name: tr('Alle Noten', 'All music'),
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
                  tr(
                    'Dieser Ordner ist noch leer.\n\n'
                        'Lege Stücke hinein: im Menü eines Stücks „In Ordner verschieben“, '
                        'mit „Mehrere auswählen“ oder mit Maus und Stift hierher ziehen. '
                        'Was du importierst, solange der Ordner offen ist, landet direkt hier.',
                    'This folder is still empty.\n\n'
                        'Put pieces in it: in a piece’s menu choose “Move to folder”, '
                        'use “Select several”, or drag them here with mouse or pen. '
                        'Whatever you import while the folder is open lands right here.',
                  ),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
        SliverPadding(
          // Unten Platz für den Importieren-Knopf, damit er keine Kachel verdeckt.
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
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
                feedback: dragFeedback(
                  context,
                  dragged.length == 1 ? e.title : tr('${dragged.length} Stücke', '${dragged.length} pieces'),
                ),
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
