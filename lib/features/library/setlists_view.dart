import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/library/library_filter.dart';
import '../../core/library/library_scanner.dart';
import '../../core/library/setlist.dart';
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
    items.add(ViewerItem(entry.path, entry.title));
  }
  return openScores(context, library, items, start: startIndex, setlistName: s.name);
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
                          title: Text(entry?.title ?? item.relativePath),
                          subtitle: entry == null
                              ? Text(
                                  'Nicht gefunden – umbenannt oder gelöscht?',
                                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                                )
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

  @override
  Widget build(BuildContext context) {
    final list = filterScores(widget.library.scores, query: _query);
    return AlertDialog(
      title: const Text('Stücke hinzufügen'),
      content: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Suchen …'),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final e = list[i];
                  final n = _selected.indexOf(e);
                  return CheckboxListTile(
                    value: n >= 0,
                    title: Text(e.title),
                    subtitle: e.composer == null ? null : Text(e.composer!),
                    secondary: n >= 0
                        ? CircleAvatar(radius: 12, child: Text('${n + 1}', style: const TextStyle(fontSize: 11)))
                        : null,
                    onChanged: (v) => setState(() => v == true ? _selected.add(e) : _selected.remove(e)),
                  );
                },
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
}

/// Fragt, zu welcher Setlist ein Stück hinzugefügt werden soll.
Future<void> addToSetlistDialog(BuildContext context, LibraryController library, ScoreEntry entry) async {
  const newOne = '__neu__';
  final choice = await showDialog<String>(
    context: context,
    builder: (c) => SimpleDialog(
      title: Text('„${entry.title}“ hinzufügen zu …'),
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
  await library.addToSetlist(target, [entry]);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Zu „${target.name}“ hinzugefügt')));
  }
}
