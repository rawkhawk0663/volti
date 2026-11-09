import 'package:flutter/material.dart';

import '../viewer/tool_controller.dart';
import '../viewer/viewer_screen.dart';
import 'library_controller.dart';
import 'setlists_view.dart';

/// Öffnet ein oder mehrere Stücke im Notenbetrachter und aktualisiert danach
/// die Bibliothek (z. B. das Anmerkungs-Symbol).
Future<void> openScores(
  BuildContext context,
  LibraryController library,
  List<ViewerItem> items, {
  int start = 0,
  String? setlistName,
}) async {
  if (items.isEmpty) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ViewerScreen(
        items: items,
        tools: ToolScope.read(context),
        startIndex: start,
        setlistName: setlistName,
        onOpened: library.settings.recordOpened,
        addBookmarkToSetlist: (ctx, path, b) async {
          final entry = library.byPath(path);
          if (entry == null) return;
          await addToSetlistDialog(ctx, library, entry, bookmark: b.id, label: b.name);
        },
      ),
    ),
  );
  for (final i in items.map((i) => i.path).toSet()) {
    await library.refreshEntry(i);
  }
  library.onLocalChange?.call(); // Anmerkungen abgleichen
}
