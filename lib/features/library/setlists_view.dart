import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/library/folders.dart';
import '../../core/library/library_filter.dart';
import '../../core/library/library_scanner.dart';
import '../../core/library/setlist.dart';
import '../viewer/export_dialog.dart';
import '../viewer/page_export.dart';
import '../viewer/viewer_screen.dart';
import 'library_controller.dart';
import 'open_scores.dart';

/// Übersicht aller Setlists.
class SetlistsView extends StatelessWidget {
  const SetlistsView({super.key, required this.library});
  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final lists = library.setlists;
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () async {
              final name = await askForName(context, title: 'Neue Setlist', initial: '');
              if (name == null || !context.mounted) return;
              final s = await library.createSetlist(name);
              if (context.mounted) await openSetlist(context, library, s);
            },
            icon: const Icon(Icons.add),
            label: const Text('Neue Setlist'),
          ),
          body: lists.isEmpty
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
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: lists.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final s = lists[i];
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: const Icon(Icons.queue_music),
                        title: Text(s.name),
                        subtitle: Text(s.items.length == 1 ? '1 Stück' : '${s.items.length} Stücke'),
                        trailing: IconButton(
                          tooltip: 'Spielen',
                          icon: const Icon(Icons.play_arrow),
                          onPressed: s.items.isEmpty ? null : () => playSetlist(context, library, s),
                        ),
                        onTap: () => openSetlist(context, library, s),
                      ),
                    );
                  },
                ),
        );
      },
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
    items.add(ViewerItem(entry.path, item.label ?? entry.title, bookmark: item.bookmark));
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
        if (library.byRelativePath(item.relativePath) case final e?) (path: e.path, bookmark: item.bookmark),
    ]),
    release: () async {
      if (opened != null) await closeExportPieces(opened!);
    },
  );
}

class SetlistDetailScreen extends StatelessWidget {
  const SetlistDetailScreen({super.key, required this.library, required this.setlist});
  final LibraryController library;
  final Setlist setlist;

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
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: s.items.isEmpty ? null : () => playSetlist(context, library, s),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Spielen'),
                ),
                const SizedBox(width: 12),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () async {
                final picked = await showScorePicker(context, library);
                if (picked != null && picked.isNotEmpty) await library.addToSetlist(s, picked);
              },
              icon: const Icon(Icons.add),
              label: const Text('Stücke hinzufügen'),
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
                            child: Text('${i + 1}', style: const TextStyle(fontSize: 12)),
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
                          subtitle: entry == null
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
                              onPressed: () {
                                s.items.removeAt(i);
                                library.saveSetlist(s);
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
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Titel, Komponist, Tonart … suchen',
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
                      if (searching) _query = '';
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
