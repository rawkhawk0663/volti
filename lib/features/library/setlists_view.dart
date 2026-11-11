import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/window_buttons.dart';
import '../../core/library/folders.dart';
import '../../core/library/library_filter.dart';
import '../../core/library/library_scanner.dart';
import '../../core/library/setlist.dart';
import '../viewer/export_dialog.dart';
import '../viewer/page_export.dart';
import '../viewer/viewer_screen.dart';
import 'folder_widgets.dart';
import 'library_actions.dart';
import 'library_controller.dart';
import 'sync_controller.dart';
import 'open_scores.dart';

/// Übersicht aller Setlists – mit Suche, Ordnern und Mehrfachauswahl
/// (wie die Bibliothek).
class SetlistsView extends StatefulWidget {
  const SetlistsView({super.key, required this.library, required this.sync, this.reset, this.active = true});

  /// Gerade sichtbar? (Nur dann wirkt die Zurück-Taste hier.)
  final bool active;
  final LibraryController library;
  final SyncController sync;

  /// Meldet „zurück zur Übersicht“ (nochmals auf Setlists getippt).
  final ValueListenable<int>? reset;

  @override
  State<SetlistsView> createState() => _SetlistsViewState();
}

class _SetlistsViewState extends State<SetlistsView> with LibraryActions {
  @override
  LibraryController get library => widget.library;
  @override
  SyncController get syncController => widget.sync;

  final _search = TextEditingController();
  String _query = '';
  String? _folder;
  bool _all = false;
  bool _selecting = false;
  final Set<String> _selected = {};

  FolderBook get _book => library.setlistFolders;
  String? get _current => _all ? null : _book.tree.resolve(_folder);

  /// Offene Setlist (in der Übersicht, damit die Seitenleiste sichtbar bleibt).
  String? _detailId;

  void _openDetail(Setlist s) => setState(() => _detailId = s.id);
  void _closeDetail() => setState(() => _detailId = null);

  @override
  void initState() {
    super.initState();
    widget.reset?.addListener(_toTop);
  }

  /// Nochmals auf „Setlists“ getippt: zurück zur Übersicht.
  void _toTop() {
    if (!mounted) return;
    setState(() {
      _detailId = null;
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
    widget.reset?.removeListener(_toTop);
    _search.dispose();
    super.dispose();
  }

  void _clearSearch() => setState(() {
    _search.clear();
    _query = '';
  });

  void _open(String? folder, {bool all = false}) => setState(() {
    _folder = folder;
    _all = all;
  });

  void _up() => _all ? _open(null) : _open(_current == null ? null : _book.tree.parentOf(_current!));

  String _folderName(String? id) => id == null ? 'Setlists' : (_book.tree.byId(id)?.name ?? 'Ordner');

  List<Setlist> get _selectedLists => [
    for (final s in library.setlists)
      if (_selected.contains(s.id)) s,
  ];

  void _endSelecting() => setState(() {
    _selecting = false;
    _selected.clear();
  });

  // ------------------------------------------------------------ Aktionen
  Future<void> _newSetlist() async {
    final name = await askForName(context, title: 'Neue Setlist', initial: '');
    if (name == null || !mounted) return;
    final s = await library.createSetlist(name);
    final folder = _current;
    if (folder != null) await library.moveSetlists([s], folder);
    if (mounted) _openDetail(s);
  }

  Future<void> _newFolder() async {
    final parent = _current;
    final name = await askForName(
      context,
      title: parent == null ? 'Neuer Ordner' : 'Neuer Ordner in „${_folderName(parent)}“',
      initial: '',
    );
    if (name != null) await _book.create(name, parent: parent);
  }

  Future<void> _rename(Setlist s) async {
    final name = await askForName(context, title: 'Setlist umbenennen', initial: s.name);
    if (name == null) return;
    s.name = name;
    await library.saveSetlist(s);
  }

  Future<void> _move(List<Setlist> lists) async {
    if (lists.isEmpty) return;
    final folders = {for (final s in lists) library.setlistFolderOf(s)};
    final to = await pickFolder(
      context,
      library,
      setlists: true,
      title: lists.length == 1
          ? '„${lists.first.name}“ verschieben nach …'
          : '${lists.length} Setlists verschieben nach …',
      current: folders.length == 1 ? folders.first : '__keiner__',
    );
    if (to == null) return;
    await library.moveSetlists(lists, to.folder);
    if (mounted && _selecting) _endSelecting();
  }

  Future<void> _delete(List<Setlist> lists) async {
    if (lists.isEmpty) return;
    final one = lists.length == 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(one ? 'Setlist löschen?' : '${lists.length} Setlists löschen?'),
        content: Text(
          '${one ? '„${lists.first.name}“ wird' : 'Die ${lists.length} Setlists werden'} gelöscht. '
          'Die Noten selbst bleiben erhalten.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    await library.deleteSetlists(lists);
    if (mounted && _selecting) _endSelecting();
  }

  Future<void> _renameFolder(ScoreFolder f) async {
    final name = await askForName(context, title: 'Ordner umbenennen', initial: f.name);
    if (name != null) await _book.rename(f, name);
  }

  Future<void> _moveFolder(ScoreFolder f) async {
    final to = await pickFolder(
      context,
      library,
      setlists: true,
      title: '„${f.name}“ verschieben nach …',
      current: _book.tree.parentOf(f.id),
      exclude: f.id,
    );
    if (to != null) await _book.move(f, to.folder);
  }

  Future<void> _deleteFolder(ScoreFolder f) async {
    final n = library.setlistCountIn(f.id);
    final parent = _book.tree.parentOf(f.id);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Ordner „${f.name}“ löschen?'),
        content: Text(
          '${n == 0
              ? 'Der Ordner ist leer.'
              : n == 1
              ? 'Die Setlist darin wird nicht gelöscht.'
              : 'Die $n Setlists darin werden nicht gelöscht.'} '
          'Was im Ordner liegt, kommt nach „${_folderName(parent)}“.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ordner löschen')),
        ],
      ),
    );
    if (ok != true) return;
    await _book.delete(f);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        persist: false,
        duration: const Duration(seconds: 6),
        content: Text('Ordner „${f.name}“ gelöscht'),
        action: SnackBarAction(label: 'Rückgängig', onPressed: () => _book.restore(f)),
      ),
    );
  }

  List<PopupMenuEntry<VoidCallback>> _folderMenu(ScoreFolder f) => [
    PopupMenuItem(
      value: () => _open(f.id),
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

  List<PopupMenuEntry<VoidCallback>> _menu(Setlist s) => [
    PopupMenuItem(
      value: () => _openDetail(s),
      child: const ListTile(leading: Icon(Icons.open_in_new), title: Text('Öffnen')),
    ),
    if (s.items.isNotEmpty)
      PopupMenuItem(
        value: () => playSetlist(context, library, s),
        child: const ListTile(leading: Icon(Icons.play_arrow), title: Text('Spielen')),
      ),
    PopupMenuItem(
      value: () => _rename(s),
      child: const ListTile(leading: Icon(Icons.edit_outlined), title: Text('Umbenennen …')),
    ),
    PopupMenuItem(
      value: () => _move([s]),
      child: const ListTile(leading: Icon(Icons.drive_file_move_outline), title: Text('In Ordner verschieben …')),
    ),
    if (s.items.isNotEmpty)
      PopupMenuItem(
        value: () => _exportSetlist(context, library, s),
        child: const ListTile(leading: Icon(Icons.ios_share), title: Text('Als PDF teilen …')),
      ),
    if (!_selecting)
      PopupMenuItem(
        value: () => setState(() {
          _selecting = true;
          _selected
            ..clear()
            ..add(s.id);
        }),
        child: const ListTile(leading: Icon(Icons.checklist), title: Text('Mehrere auswählen')),
      ),
    const PopupMenuDivider(),
    PopupMenuItem(
      value: () => _delete([s]),
      child: const ListTile(leading: Icon(Icons.delete_outline), title: Text('Löschen …')),
    ),
  ];

  // ---------------------------------------------------------------- Aufbau
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final id = _detailId;
        final open = id == null ? null : library.setlists.where((s) => s.id == id).firstOrNull;
        if (open != null) {
          // Offene Setlist innerhalb der Übersicht: Die Seitenleiste bleibt.
          return PopScope(
            canPop: !widget.active,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && widget.active) _closeDetail();
            },
            child: SetlistDetailScreen(
              key: ValueKey('setlist/$id'),
              library: library,
              setlist: open,
              onBack: _closeDetail,
            ),
          );
        }
        return _build(context);
      },
    );
  }

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final tree = _book.tree;
    final searching = _query.trim().isNotEmpty;
    final current = _current;
    final words = _query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    // Suche: im Namen der Setlist oder in den Titeln ihrer Songs.
    bool matches(Setlist s) {
      final hay = [
        s.name,
        for (final i in s.items) i.label ?? library.byRelativePath(i.relativePath)?.title ?? '',
      ].join(' ').toLowerCase();
      return words.every(hay.contains);
    }

    final lists = (searching || _all ? library.setlists.where(matches).toList() : library.setlistsIn(current))
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final folders = _all
        ? const <ScoreFolder>[]
        : searching
        ? [
            for (final f in tree.live)
              if (words.every(f.name.toLowerCase().contains)) f,
          ]
        : tree.children(current);
    final showAll = !searching && !_all && current == null && tree.live.isNotEmpty;
    final chosen = _selectedLists;

    Widget header;
    if (_selecting) {
      final allChosen = lists.isNotEmpty && lists.every((s) => _selected.contains(s.id));
      header = Padding(
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
                    chosen.isEmpty
                        ? 'Setlists antippen zum Auswählen'
                        : chosen.length == 1
                        ? '1 Setlist ausgewählt'
                        : '${chosen.length} Setlists ausgewählt',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  onPressed: lists.isEmpty
                      ? null
                      : () => setState(() {
                          if (allChosen) {
                            _selected.removeAll(lists.map((s) => s.id));
                          } else {
                            _selected.addAll(lists.map((s) => s.id));
                          }
                        }),
                  child: Text(allChosen ? 'Keine' : 'Alle'),
                ),
                IconButton(
                  tooltip: 'In Ordner verschieben',
                  onPressed: chosen.isEmpty ? null : () => _move(chosen),
                  icon: const Icon(Icons.drive_file_move_outline),
                ),
                IconButton(
                  tooltip: 'Löschen',
                  onPressed: chosen.isEmpty ? null : () => _delete(chosen),
                  icon: const Icon(Icons.delete_outline),
                ),
                const WindowButtons(),
              ],
            ),
          ),
        ),
      );
    } else {
      header = Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: SearchBar(
                controller: _search,
                hintText: 'Setlist oder Song suchen',
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
              onPressed: library.setlists.isEmpty ? null : () => setState(() => _selecting = true),
              icon: const Icon(Icons.checklist),
            ),
            ...headerActions(),
          ],
        ),
      );
    }

    Widget crumbs() {
      final path = tree.pathTo(current);
      Widget crumb(String? id, String label, {required bool last}) => FolderDropTarget(
        library: library,
        folder: id,
        setlists: true,
        builder: (context, hovering) => Container(
          decoration: BoxDecoration(
            color: hovering ? theme.colorScheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: last ? null : () => _open(id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                label,
                style: last
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
          ),
        ),
      );
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
                      crumb(null, 'Setlists', last: false),
                      if (_all) ...[
                        sep,
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text('Alle Setlists', style: theme.textTheme.titleMedium),
                        ),
                      ],
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
                itemBuilder: (_) => _folderMenu(tree.byId(current)!).skip(1).toList(),
              ),
          ],
        ),
      );
    }

    String count(int n) => n == 1 ? '1 Setlist' : '$n Setlists';
    final empty = library.setlists.isEmpty && tree.live.isEmpty;

    return PopScope(
      canPop: !widget.active || (!_selecting && !_all && current == null),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !widget.active) return;
        _selecting ? _endSelecting() : _up();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: _selecting
            ? null
            : FloatingActionButton.extended(
                onPressed: _newSetlist,
                icon: const Icon(Icons.add),
                label: const Text('Neue Setlist'),
              ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            if ((current != null || _all) && !searching) crumbs(),
            Expanded(
              child: empty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Noch keine Setlists.\nEine Setlist ist eine Reihenfolge von Stücken, z. B. für ein Konzert. '
                          'Beim Spielen geht es nach der letzten Seite direkt zum nächsten Stück.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    )
                  : CustomScrollView(
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
                                    library: library,
                                    setlists: true,
                                    icon: Icons.queue_music_outlined,
                                    name: 'Alle Setlists',
                                    subtitle: count(library.setlists.length),
                                    onOpen: () => _open(null, all: true),
                                  ),
                                for (final f in folders)
                                  FolderTile(
                                    key: ValueKey('sfolder/${f.id}'),
                                    library: library,
                                    setlists: true,
                                    folder: f,
                                    icon: Icons.folder,
                                    name: f.name,
                                    subtitle: count(library.setlistCountIn(f.id)),
                                    onOpen: () {
                                      if (searching) _clearSearch();
                                      _open(f.id);
                                    },
                                    menuBuilder: (_) => _folderMenu(f),
                                  ),
                              ]),
                            ),
                          ),
                        if (lists.isEmpty && folders.isEmpty && !showAll)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Text(
                                searching ? 'Keine Treffer.' : 'Dieser Ordner ist noch leer.',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                          sliver: SliverList.separated(
                            itemCount: lists.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, i) => _tile(context, lists[i], showFolder: searching || _all),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, Setlist s, {required bool showFolder}) {
    final selected = _selecting ? _selected.contains(s.id) : null;
    final folder = showFolder ? library.setlistFolderOf(s) : null;
    final sub = [
      s.items.length == 1 ? '1 Stück' : '${s.items.length} Stücke',
      if (folder != null) '📁 ${_folderName(folder)}',
    ].join(' · ');
    Future<void> menuAt(Offset at) async {
      final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
      final action = await showMenu<VoidCallback>(
        context: context,
        position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
        items: _menu(s),
      );
      action?.call();
    }

    final card = Card(
      margin: EdgeInsets.zero,
      color: selected == true ? Theme.of(context).colorScheme.primaryContainer : null,
      child: Builder(
        builder: (context) => ListTile(
          leading: selected == null
              ? const Icon(Icons.queue_music)
              : Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked),
          title: Text(s.name),
          subtitle: Text(sub),
          trailing: _selecting
              ? null
              : IconButton(
                  tooltip: 'Spielen',
                  icon: const Icon(Icons.play_arrow),
                  onPressed: s.items.isEmpty ? null : () => playSetlist(context, library, s),
                ),
          onTap: _selecting
              ? () => setState(() => _selected.contains(s.id) ? _selected.remove(s.id) : _selected.add(s.id))
              : () => _openDetail(s),
          onLongPress: () {
            final box = context.findRenderObject() as RenderBox;
            menuAt(box.localToGlobal(box.size.center(Offset.zero)));
          },
        ),
      ),
    );
    final dragged = selected == true ? _selectedLists : [s];
    return GestureDetector(
      onSecondaryTapUp: (d) => menuAt(d.globalPosition),
      child: PointerDraggable<LibraryDrag>(
        key: ValueKey(s.id),
        data: LibraryDrag(setlists: dragged),
        feedback: dragFeedback(
          context,
          dragged.length == 1 ? s.name : '${dragged.length} Setlists',
          icon: Icons.queue_music,
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: card),
        child: card,
      ),
    );
  }
}

Future<void> openSetlist(BuildContext context, LibraryController library, Setlist s) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => SetlistDetailScreen(library: library, setlist: s),
  ),
);

/// Spielt die Setlist ab [start] ab. Fehlende Stücke werden übersprungen.
Future<void> playSetlist(BuildContext context, LibraryController library, Setlist s, {int start = 0}) {
  final items = <ViewerItem>[];
  var startIndex = 0;
  for (var i = 0; i < s.items.length; i++) {
    final entry = library.byRelativePath(s.items[i].relativePath);
    if (entry == null) continue;
    if (i == start) startIndex = items.length;
    final item = s.items[i];
    items.add(
      ViewerItem(entry.path, item.label ?? entry.title, bookmark: item.bookmark, setlistId: s.id, setlistName: s.name),
    );
  }
  return openScores(context, library, items, start: startIndex, setlistName: s.name);
}

/// Alle Stücke einer Setlist als ein PDF – in der Reihenfolge der Setlist.
Future<void> _exportSetlist(BuildContext context, LibraryController library, Setlist s) async {
  List<ExportPiece>? opened;
  await showExportDialog(
    context,
    title: s.name,
    load: () async => opened ??= await openExportPieces([
      for (final item in s.items)
        if (library.byRelativePath(item.relativePath) case final e?)
          (path: e.path, bookmark: item.bookmark, scope: s.id),
    ]),
    release: () async {
      if (opened != null) await closeExportPieces(opened!);
    },
  );
}

class SetlistDetailScreen extends StatelessWidget {
  const SetlistDetailScreen({super.key, required this.library, required this.setlist, this.onBack});
  final LibraryController library;
  final Setlist setlist;

  /// Zurück zur Übersicht (wenn sie in der Übersicht steckt statt als eigene Seite).
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final s = setlist;
        return VoltiBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              leading: onBack == null
                  ? null
                  : IconButton(
                      tooltip: 'Zurück zu den Setlists',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: onBack,
                    ),
              automaticallyImplyLeading: onBack == null,
              title: Text(s.name),
              actions: [
                IconButton(
                  tooltip: 'Ganze Setlist als PDF (z. B. für die Band)',
                  icon: const Icon(Icons.ios_share),
                  onPressed: s.items.isEmpty ? null : () => _exportSetlist(context, library, s),
                ),
                IconButton(
                  tooltip: 'Umbenennen',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final name = await askForName(context, title: 'Setlist umbenennen', initial: s.name);
                    if (name == null) return;
                    s.name = name;
                    await library.saveSetlist(s);
                  },
                ),
                IconButton(
                  tooltip: 'Setlist löschen',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Setlist löschen?'),
                        content: Text('„${s.name}“ wird gelöscht. Die Noten selbst bleiben erhalten.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
                          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Löschen')),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    await library.deleteSetlist(s);
                    if (!context.mounted) return;
                    if (onBack != null) {
                      onBack!();
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: s.items.isEmpty ? null : () => playSetlist(context, library, s),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Spielen'),
                ),
                const SizedBox(width: 8),
                const WindowButtons(),
                const SizedBox(width: 4),
              ],
            ),
            floatingActionButton: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'sheet',
                  tooltip: 'Leeres Blatt für Notizen (z. B. als Music Director)',
                  onPressed: () async {
                    final name = await askForName(context, title: 'Neues Notizblatt', initial: 'Notizen');
                    if (name == null) return;
                    final sheet = await library.createSheet(name);
                    if (sheet != null) await library.addToSetlist(s, [sheet]);
                  },
                  icon: const Icon(Icons.sticky_note_2_outlined),
                  label: const Text('Notizblatt'),
                ),
                const SizedBox(width: 12),
                FloatingActionButton.extended(
                  heroTag: 'add',
                  onPressed: () async {
                    final picked = await showScorePicker(context, library);
                    if (picked != null && picked.isNotEmpty) await library.addToSetlist(s, picked);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Stücke hinzufügen'),
                ),
              ],
            ),
            body: s.items.isEmpty
                ? const Center(child: Text('Noch leer. Füge Stücke hinzu.'))
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: s.items.length,
                    onReorderItem: (from, to) {
                      final item = s.items.removeAt(from);
                      s.items.insert(to, item);
                      library.saveSetlist(s);
                    },
                    itemBuilder: (context, i) {
                      final item = s.items[i];
                      final entry = library.byRelativePath(item.relativePath);
                      return Card(
                        key: ValueKey(item.id),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            radius: 14,
                            child: entry?.isSheet == true
                                ? const Icon(Icons.sticky_note_2_outlined, size: 16)
                                : Text('${i + 1}', style: const TextStyle(fontSize: 12)),
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  item.label ?? entry?.title ?? item.relativePath,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (entry?.musicalKey != null) ...[
                                const SizedBox(width: 8),
                                KeyBadge(entry!.musicalKey!),
                              ],
                            ],
                          ),
                          subtitle: entry?.isSheet == true
                              ? const Text('Notizblatt – zum Beschreiben; mehr Seiten über ⋮ → Leere Seite einfügen')
                              : entry == null
                              ? Text(
                                  'Nicht gefunden – umbenannt oder gelöscht?',
                                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                                )
                              : item.bookmark != null
                              ? Text('Lesezeichen in «${entry.title}»')
                              : (entry.composer == null ? null : Text(entry.composer!)),
                          onTap: entry == null ? null : () => playSetlist(context, library, s, start: i),
                          trailing: Padding(
                            padding: const EdgeInsets.only(right: 24), // Platz für den Zieh-Griff
                            child: IconButton(
                              tooltip: 'Aus Setlist entfernen',
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () async {
                                if (entry?.isSheet == true && entry!.hasAnnotations) {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: Text('Notizblatt „${entry.title}“ entfernen?'),
                                      content: const Text('Deine Notizen darauf werden gelöscht.'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(c, false),
                                          child: const Text('Abbrechen'),
                                        ),
                                        FilledButton(
                                          onPressed: () => Navigator.pop(c, true),
                                          child: const Text('Entfernen'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok != true) return;
                                }
                                await library.removeFromSetlist(s, i);
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}

Future<String?> askForName(BuildContext context, {required String title, required String initial}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      void submit() {
        final v = c.text.trim();
        if (v.isNotEmpty) Navigator.pop(ctx, v);
      }

      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (_) => submit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: submit, child: const Text('OK')),
        ],
      );
    },
  ).whenComplete(c.dispose);
}

/// Auswahl-Dialog: Stücke suchen und mehrere ankreuzen.
Future<List<ScoreEntry>?> showScorePicker(BuildContext context, LibraryController library) {
  return showDialog<List<ScoreEntry>>(
    context: context,
    builder: (_) => _ScorePicker(library: library),
  );
}

class _ScorePicker extends StatefulWidget {
  const _ScorePicker({required this.library});
  final LibraryController library;

  @override
  State<_ScorePicker> createState() => _ScorePickerState();
}

class _ScorePickerState extends State<_ScorePicker> {
  String _query = '';
  final _search = TextEditingController();

  void _clearSearch() => setState(() {
    _search.clear();
    _query = '';
  });

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  final List<ScoreEntry> _selected = [];

  /// Offener Ordner (null = oberste Ebene) bzw. "Alle Noten".
  String? _folder;
  bool _all = false;

  LibraryController get lib => widget.library;

  void _open(String? folder, {bool all = false}) => setState(() {
    _folder = folder;
    _all = all;
  });

  void _toggle(ScoreEntry e) => setState(() => _selected.contains(e) ? _selected.remove(e) : _selected.add(e));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tree = lib.folders;
    final searching = _query.trim().isNotEmpty;
    final current = _all ? null : tree.resolve(_folder);
    // Gleiche Titel stehen zusammen, nach Tonart geordnet (z. B. ein Lied in
    // mehreren Tonarten).
    final list = filterScores(searching || _all ? lib.scores : lib.scoresIn(current), query: _query);
    final words = _query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final folders = _all
        ? const <ScoreFolder>[]
        : searching
        ? [
            for (final f in tree.live)
              if (words.every(f.name.toLowerCase().contains)) f,
          ]
        : tree.children(current);
    final showAll = !searching && !_all && current == null && tree.live.isNotEmpty;
    final path = tree.pathTo(current);
    final size = MediaQuery.sizeOf(context);

    Widget folderRow(IconData icon, String name, String sub, VoidCallback onTap) => ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(name),
      subtitle: Text(sub),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );

    String count(int n) => n == 1 ? '1 Stück' : '$n Stücke';

    return AlertDialog(
      title: const Text('Stücke hinzufügen'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: math.min(640, size.width - 48),
        height: math.min(620, size.height - 220),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Titel, Komponist, Tonart … suchen',
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(tooltip: 'Suche leeren', icon: const Icon(Icons.close), onPressed: _clearSearch),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            if (!searching && (current != null || _all))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Zurück',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => _all ? _open(null) : _open(tree.parentOf(current!)),
                    ),
                    Expanded(
                      child: Text(
                        ['Bibliothek', if (_all) 'Alle Noten', for (final f in path) f.name].join(' › '),
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView(
                children: [
                  if (showAll)
                    folderRow(
                      Icons.library_books_outlined,
                      'Alle Noten',
                      count(lib.scores.length),
                      () => _open(null, all: true),
                    ),
                  for (final f in folders)
                    folderRow(Icons.folder, f.name, count(lib.countIn(f.id)), () {
                      if (searching) _clearSearch();
                      _open(f.id);
                    }),
                  if ((showAll || folders.isNotEmpty) && list.isNotEmpty) const Divider(),
                  for (final e in list) _scoreRow(context, e, showFolder: searching || _all),
                  if (list.isEmpty && folders.isEmpty && !showAll)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        searching ? 'Keine Treffer.' : 'Hier liegen keine Stücke.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, _selected),
          child: Text(_selected.isEmpty ? 'Hinzufügen' : '${_selected.length} hinzufügen'),
        ),
      ],
    );
  }

  Widget _scoreRow(BuildContext context, ScoreEntry e, {required bool showFolder}) {
    final n = _selected.indexOf(e);
    final folder = showFolder ? lib.folderOf(e) : null;
    final sub = [?e.composer, if (folder != null) '📁 ${lib.folders.byId(folder)?.name ?? ''}'].join(' · ');
    return CheckboxListTile(
      value: n >= 0,
      controlAffinity: ListTileControlAffinity.leading,
      title: Row(
        children: [
          Flexible(child: Text(e.title, overflow: TextOverflow.ellipsis)),
          if (e.musicalKey != null) ...[const SizedBox(width: 8), KeyBadge(e.musicalKey!)],
        ],
      ),
      subtitle: sub.isEmpty ? null : Text(sub, overflow: TextOverflow.ellipsis),
      secondary: n >= 0
          ? CircleAvatar(radius: 12, child: Text('${n + 1}', style: const TextStyle(fontSize: 11)))
          : null,
      onChanged: (_) => _toggle(e),
    );
  }
}

/// Tonart als gut sichtbares Schild, z. B. „G-Dur“.
class KeyBadge extends StatelessWidget {
  const KeyBadge(this.musicalKey, {super.key});
  final String musicalKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(6)),
      child: Text(
        musicalKey,
        style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );
  }
}

/// Fragt, zu welcher Setlist ein Stück hinzugefügt werden soll.
Future<void> addToSetlistDialog(
  BuildContext context,
  LibraryController library,
  ScoreEntry entry, {
  String? bookmark,
  String? label,
}) => addManyToSetlistDialog(context, library, [entry], bookmark: bookmark, label: label);

/// Ein oder mehrere Stücke (bzw. ein Lesezeichen) zu einer Setlist hinzufügen.
Future<void> addManyToSetlistDialog(
  BuildContext context,
  LibraryController library,
  List<ScoreEntry> entries, {
  String? bookmark,
  String? label,
}) async {
  if (entries.isEmpty) return;
  const newOne = '__neu__';
  final what = entries.length == 1 ? '„${label ?? entries.first.title}“' : '${entries.length} Stücke';
  final choice = await showDialog<String>(
    context: context,
    builder: (c) => SimpleDialog(
      title: Text('$what hinzufügen zu …'),
      children: [
        for (final s in library.setlists)
          SimpleDialogOption(onPressed: () => Navigator.pop(c, s.id), child: Text(s.name)),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(c, newOne),
          child: const Row(children: [Icon(Icons.add, size: 18), SizedBox(width: 8), Text('Neue Setlist …')]),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  Setlist? target;
  if (choice == newOne) {
    final name = await askForName(context, title: 'Neue Setlist', initial: '');
    if (name == null) return;
    target = await library.createSetlist(name);
  } else {
    target = library.setlists.firstWhere((s) => s.id == choice);
  }
  if (bookmark != null) {
    await library.addBookmarkToSetlist(target, entries.first, bookmark, label ?? entries.first.title);
  } else {
    await library.addToSetlist(target, entries);
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Zu „${target.name}“ hinzugefügt')));
  }
}
