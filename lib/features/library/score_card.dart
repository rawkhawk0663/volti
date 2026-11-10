import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/library/library_scanner.dart';
import '../../core/pdf/thumbnail_cache.dart';

/// Vorschaubild der ersten Seite (wird im Hintergrund erzeugt).
class ScoreThumbnail extends StatefulWidget {
  const ScoreThumbnail({super.key, required this.path});
  final String path;

  @override
  State<ScoreThumbnail> createState() => _ScoreThumbnailState();
}

class _ScoreThumbnailState extends State<ScoreThumbnail> {
  File? _file;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ScoreThumbnail old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _file = null;
      _load();
    }
  }

  Future<void> _load() async {
    final path = widget.path;
    final f = await (await ThumbnailCache.instance()).thumbnailFor(path);
    if (mounted && path == widget.path) setState(() => _file = f);
  }

  @override
  Widget build(BuildContext context) {
    final f = _file;
    if (f == null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(child: Icon(Icons.music_note, size: 32, color: Theme.of(context).colorScheme.outline)),
      );
    }
    return ColoredBox(
      color: Colors.white,
      child: Image.file(f, fit: BoxFit.cover, alignment: Alignment.topCenter, cacheWidth: ThumbnailCache.width),
    );
  }
}

/// Kachel eines Stücks in der Bibliothek.
class ScoreCard extends StatelessWidget {
  const ScoreCard({
    super.key,
    required this.entry,
    required this.onOpen,
    required this.menuBuilder,
    this.selected,
    this.folderName,
  });

  final ScoreEntry entry;
  final VoidCallback onOpen;

  /// Im Auswahl-Modus: angekreuzt oder nicht (null = kein Auswahl-Modus).
  final bool? selected;

  /// Ordner, in dem das Stück liegt (wird bei der Suche angezeigt).
  final String? folderName;
  final List<PopupMenuEntry<VoidCallback>> Function(BuildContext) menuBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        onSecondaryTapUp: (d) => _showMenu(context, d.globalPosition),
        onLongPress: () {
          final box = context.findRenderObject() as RenderBox;
          _showMenu(context, box.localToGlobal(box.size.center(Offset.zero)));
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ScoreThumbnail(path: entry.path),
                  if (selected == true) ColoredBox(color: theme.colorScheme.primary.withValues(alpha: 0.28)),
                  if (selected != null)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Icon(
                        selected! ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 28,
                        color: selected! ? theme.colorScheme.primary : Colors.black54,
                        shadows: const [Shadow(color: Colors.white, blurRadius: 4)],
                      ),
                    ),
                  if (folderName != null)
                    Positioned(
                      left: 6,
                      right: 6,
                      bottom: 6,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.folder_outlined, size: 13, color: theme.colorScheme.onSecondaryContainer),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  folderName!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (entry.hasAnnotations)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Tooltip(
                        message: 'Mit Anmerkungen',
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: theme.colorScheme.primary,
                          child: const Icon(Icons.edit, size: 13, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 2, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          entry.composer ?? ' ',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<VoidCallback>(
                    tooltip: 'Mehr',
                    icon: const Icon(Icons.more_vert, size: 20),
                    itemBuilder: menuBuilder,
                    onSelected: (action) => action(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context, Offset at) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: menuBuilder(context),
    );
    action?.call();
  }
}
