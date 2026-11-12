import 'package:flutter/material.dart';

import '../../core/ink/navigation_marks.dart';
import 'ink_controller.dart';
import '../../app/l10n.dart';

/// Lesezeichen eines Stücks: anspringen, anlegen, umbenennen, Bereich ändern,
/// löschen – und als eigenes Stück in eine Setlist legen.
///
/// [shown]: angezeigte Seiten als PDF-Seitennummern (Anzeige-Reihenfolge),
/// [current]: aktuell angezeigte Seite (1-basiert).
Future<void> showBookmarks(
  BuildContext context, {
  required InkController ink,
  required List<int> shown,
  required int current,
  required ValueChanged<int> onOpen,
  Future<void> Function(Bookmark b)? onAddToSetlist,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) =>
      _BookmarksSheet(ink: ink, shown: shown, current: current, onOpen: onOpen, onAddToSetlist: onAddToSetlist),
);

class _BookmarksSheet extends StatelessWidget {
  const _BookmarksSheet({
    required this.ink,
    required this.shown,
    required this.current,
    required this.onOpen,
    required this.onAddToSetlist,
  });

  final InkController ink;
  final List<int> shown;
  final int current;
  final ValueChanged<int> onOpen;
  final Future<void> Function(Bookmark b)? onAddToSetlist;

  /// Angezeigte Seite (1-basiert) einer PDF-Seite, 0 = ausgeblendet.
  int _display(int pdfPage) => shown.indexOf(pdfPage) + 1;

  String _range(Bookmark b) {
    final a = _display(b.page), e = _display(b.lastPage);
    if (a == 0) return tr('Seite ausgeblendet', 'Page hidden');
    return e > a ? tr('Seiten $a–$e', 'Pages $a–$e') : tr('Seite $a', 'Page $a');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: ink,
      builder: (context, _) {
        final marks = ink.annotations.bookmarks;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(tr('Lesezeichen', 'Bookmarks'), style: Theme.of(context).textTheme.titleLarge),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _edit(context, null),
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: Text(tr('Seite $current merken', 'Bookmark page $current')),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    tr(
                      'Zum Beispiel ein Lied in einem Sammelband. Antippen springt hin. Mit einem Seitenbereich lässt '
                          'es sich als eigenes Stück in eine Setlist legen.',
                      'For example a song in a songbook. Tap to jump there. With a page range it can '
                          'be put into a setlist as a piece of its own.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                if (marks.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text(tr('Noch keine Lesezeichen.', 'No bookmarks yet.'))),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final b in marks)
                          ListTile(
                            leading: Icon(Icons.bookmark, color: scheme.primary),
                            title: Text(b.name),
                            subtitle: Text(_range(b)),
                            onTap: _display(b.page) == 0
                                ? null
                                : () {
                                    Navigator.of(context).pop();
                                    onOpen(_display(b.page));
                                  },
                            onLongPress: () => _edit(context, b),
                            trailing: PopupMenuButton<String>(
                              tooltip: tr('Mehr', 'More'),
                              onSelected: (v) async {
                                if (v == 'edit') await _edit(context, b);
                                if (v == 'setlist') await onAddToSetlist?.call(b);
                                if (v == 'delete') ink.deleteBookmark(b.id);
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(value: 'edit', child: Text(tr('Name und Seiten …', 'Name and pages …'))),
                                if (onAddToSetlist != null)
                                  PopupMenuItem(
                                    value: 'setlist',
                                    child: Text(tr('Zu Setlist hinzufügen …', 'Add to setlist …')),
                                  ),
                                PopupMenuItem(value: 'delete', child: Text(tr('Löschen', 'Delete'))),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Neues Lesezeichen (ab der aktuellen Seite) oder bestehendes ändern.
  Future<void> _edit(BuildContext context, Bookmark? b) async {
    final result = await showDialog<({String name, int from, int to})>(
      context: context,
      builder: (_) => _BookmarkDialog(
        initialName: b?.name ?? '',
        from: b == null ? current : _display(b.page).clamp(1, shown.length),
        to: b == null ? current : _display(b.lastPage).clamp(1, shown.length),
        pageCount: shown.length,
      ),
    );
    if (result == null) return;
    final page = shown[result.from - 1];
    final end = result.to > result.from ? shown[result.to - 1] : null;
    if (b == null) {
      ink.addBookmark(name: result.name, page: page, endPage: end);
    } else {
      ink.updateBookmark(
        b.copyWith(name: result.name.trim().isEmpty ? b.name : result.name.trim(), page: page, endPage: end),
      );
    }
  }
}

class _BookmarkDialog extends StatefulWidget {
  const _BookmarkDialog({required this.initialName, required this.from, required this.to, required this.pageCount});
  final String initialName;
  final int from, to, pageCount;

  @override
  State<_BookmarkDialog> createState() => _BookmarkDialogState();
}

class _BookmarkDialogState extends State<_BookmarkDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  late int _from = widget.from, _to = widget.to;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Widget _picker(String label, int value, int min, ValueChanged<int> onChanged) => Row(
    children: [
      SizedBox(width: 90, child: Text(label)),
      IconButton(onPressed: value > min ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove)),
      SizedBox(width: 40, child: Text('$value', textAlign: TextAlign.center)),
      IconButton(onPressed: value < widget.pageCount ? () => onChanged(value + 1) : null, icon: const Icon(Icons.add)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Lesezeichen', 'Bookmark')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(
              labelText: tr('Name', 'Name'),
              hintText: tr('z. B. Autumn Leaves', 'e.g. Autumn Leaves'),
            ),
          ),
          const SizedBox(height: 12),
          _picker(
            tr('Ab Seite', 'From page'),
            _from,
            1,
            (v) => setState(() {
              _from = v;
              if (_to < _from) _to = _from;
            }),
          ),
          _picker(tr('Bis Seite', 'To page'), _to, _from, (v) => setState(() => _to = v)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Abbrechen', 'Cancel'))),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((name: _name.text, from: _from, to: _to)),
          child: Text(tr('Speichern', 'Save')),
        ),
      ],
    );
  }
}
