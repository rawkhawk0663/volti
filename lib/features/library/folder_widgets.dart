import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/library/folders.dart';
import '../../core/library/library_scanner.dart';
import '../../core/library/setlist.dart';
import 'library_controller.dart';
import 'setlists_view.dart';
import '../../app/l10n.dart';

/// Was gezogen wird: Stücke, Setlists oder ein Ordner.
class LibraryDrag {
  const LibraryDrag({this.scores = const [], this.setlists = const [], this.folder, this.setlistFolder = false});
  final List<ScoreEntry> scores;
  final List<Setlist> setlists;
  final ScoreFolder? folder;

  /// Gehört [folder] zu den Setlist-Ordnern?
  final bool setlistFolder;
}

/// Ziehen nur mit Maus und Stift. Mit dem Finger wird gescrollt (und langes
/// Drücken öffnet das Menü); zum Verschieben gibt es dort "In Ordner …".
class PointerDraggable<T extends Object> extends Draggable<T> {
  const PointerDraggable({
    super.key,
    required super.child,
    required super.feedback,
    super.data,
    super.childWhenDragging,
    super.dragAnchorStrategy = pointerDragAnchorStrategy,
  });

  static const devices = {
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
  };

  @override
  MultiDragGestureRecognizer createRecognizer(GestureMultiDragStartCallback onStart) =>
      ImmediateMultiDragGestureRecognizer(supportedDevices: devices)..onStart = onStart;
}

/// Kleines Bild, das beim Ziehen am Zeiger hängt.
Widget dragFeedback(BuildContext context, String label, {IconData icon = Icons.music_note}) {
  final scheme = Theme.of(context).colorScheme;
  return Material(
    color: scheme.primaryContainer,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: scheme.onPrimaryContainer),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onPrimaryContainer),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Nimmt gezogene Stücke (bzw. Setlists) oder Ordner an und legt sie in
/// [folder] (null = oberste Ebene). [setlists]: Ordner der Setlists.
class FolderDropTarget extends StatelessWidget {
  const FolderDropTarget({
    super.key,
    required this.library,
    required this.folder,
    required this.builder,
    this.setlists = false,
  });
  final LibraryController library;
  final String? folder;
  final bool setlists;
  final Widget Function(BuildContext context, bool hovering) builder;

  FolderBook get _book => setlists ? library.setlistFolders : library.scoreFolders;

  bool _accepts(LibraryDrag d) {
    final f = d.folder;
    if (f != null) {
      if (d.setlistFolder != setlists) return false;
      return f.id != folder && (folder == null || !_book.tree.isInside(folder, f.id));
    }
    if (setlists) return d.setlists.any((s) => library.setlistFolderOf(s) != folder);
    return d.scores.any((s) => library.folderOf(s) != folder);
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<LibraryDrag>(
      onWillAcceptWithDetails: (d) => _accepts(d.data),
      onAcceptWithDetails: (d) async {
        final f = d.data.folder;
        if (f != null) {
          await _book.move(f, folder);
        } else if (setlists) {
          await library.moveSetlists(d.data.setlists, folder);
        } else {
          await library.moveScores(d.data.scores, folder);
        }
        if (!context.mounted) return;
        final where = folder == null
            ? (setlists ? tr('Setlists', 'Setlists') : tr('Bibliothek', 'Library'))
            : (_book.tree.byId(folder)?.name ?? tr('Ordner', 'Folder'));
        final n = setlists ? d.data.setlists.length : d.data.scores.length;
        final what = f != null
            ? tr('„${f.name}“', '“${f.name}”')
            : n == 1
            ? '„${setlists ? d.data.setlists.first.name : d.data.scores.first.title}“'
            : '$n ${setlists ? tr('Setlists', 'setlists') : tr('Stücke', 'pieces')}';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('$what liegt jetzt in „$where“', '$what is now in “$where”'))));
      },
      builder: (context, candidates, _) => builder(context, candidates.isNotEmpty),
    );
  }
}

/// Kachel eines Ordners.
class FolderTile extends StatelessWidget {
  const FolderTile({
    super.key,
    required this.library,
    required this.icon,
    required this.name,
    required this.subtitle,
    required this.onOpen,
    this.folder,
    this.menuBuilder,
    this.dropTarget = true,
    this.setlists = false,
  });

  /// Ordner der Setlists (statt der Bibliothek).
  final bool setlists;

  final LibraryController library;
  final IconData icon;
  final String name;
  final String subtitle;
  final VoidCallback onOpen;

  /// Der Ordner selbst (null bei "Alle Noten").
  final ScoreFolder? folder;
  final List<PopupMenuEntry<VoidCallback>> Function(BuildContext)? menuBuilder;
  final bool dropTarget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget card(bool hovering) => Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      color: hovering ? theme.colorScheme.primaryContainer : null,
      shape: hovering
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.primary, width: 2),
            )
          : null,
      child: InkWell(
        onTap: onOpen,
        onSecondaryTapUp: menuBuilder == null ? null : (d) => _showMenu(context, d.globalPosition),
        onLongPress: menuBuilder == null
            ? null
            : () {
                final box = context.findRenderObject() as RenderBox;
                _showMenu(context, box.localToGlobal(box.size.center(Offset.zero)));
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 2, 6),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (menuBuilder != null)
                PopupMenuButton<VoidCallback>(
                  tooltip: tr('Mehr', 'More'),
                  icon: const Icon(Icons.more_vert, size: 20),
                  itemBuilder: menuBuilder!,
                  onSelected: (a) => a(),
                )
              else
                const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );

    final f = folder;
    Widget tile = dropTarget && f != null
        ? FolderDropTarget(library: library, folder: f.id, setlists: setlists, builder: (context, h) => card(h))
        : card(false);
    if (f != null) {
      tile = PointerDraggable<LibraryDrag>(
        data: LibraryDrag(folder: f, setlistFolder: setlists),
        feedback: dragFeedback(context, f.name, icon: Icons.folder),
        child: tile,
      );
    }
    return tile;
  }

  Future<void> _showMenu(BuildContext context, Offset at) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: menuBuilder!(context),
    );
    action?.call();
  }
}

/// Ergebnis der Ordnerwahl ([folder] null = oberste Ebene).
class FolderChoice {
  const FolderChoice(this.folder);
  final String? folder;
}

/// Dialog: Ordner wählen (als Baum). [exclude]: dieser Ordner und alles darin
/// stehen nicht zur Wahl (beim Verschieben eines Ordners).
Future<FolderChoice?> pickFolder(
  BuildContext context,
  LibraryController library, {
  required String title,
  String? current,
  String? exclude,
  bool setlists = false,
}) async {
  const newOne = FolderChoice('__neu__');
  final book = setlists ? library.setlistFolders : library.scoreFolders;
  final tree = book.tree;
  final choice = await showDialog<FolderChoice>(
    context: context,
    builder: (c) {
      final theme = Theme.of(c);
      Widget option(String? id, String name, int depth, IconData icon) {
        final here = id == current;
        return SimpleDialogOption(
          onPressed: here ? null : () => Navigator.pop(c, FolderChoice(id)),
          padding: EdgeInsets.fromLTRB(24.0 + depth * 22, 10, 24, 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: here ? theme.disabledColor : theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  here ? tr('$name (hier)', '$name (here)') : name,
                  style: here ? TextStyle(color: theme.disabledColor) : null,
                ),
              ),
            ],
          ),
        );
      }

      return SimpleDialog(
        title: Text(title),
        children: [
          option(
            null,
            setlists
                ? tr('Setlists (kein Ordner)', 'Setlists (no folder)')
                : tr('Bibliothek (kein Ordner)', 'Library (no folder)'),
            0,
            setlists ? Icons.queue_music_outlined : Icons.library_music_outlined,
          ),
          for (final (f, depth) in tree.outline())
            if (exclude == null || !tree.isInside(f.id, exclude))
              option(f.id, f.name, depth + 1, Icons.folder_outlined),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, newOne),
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
            child: Row(
              children: [
                Icon(Icons.create_new_folder_outlined, size: 20),
                SizedBox(width: 10),
                Text(tr('Neuer Ordner …', 'New folder …')),
              ],
            ),
          ),
        ],
      );
    },
  );
  if (choice == null || !context.mounted) return null;
  if (identical(choice, newOne)) {
    final name = await askForName(context, title: tr('Neuer Ordner', 'New folder'), initial: '');
    if (name == null) return null;
    final f = await book.create(name);
    return FolderChoice(f.id);
  }
  return choice;
}
