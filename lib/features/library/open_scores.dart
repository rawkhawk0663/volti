import 'package:flutter/material.dart';

import '../viewer/viewer_screen.dart';
import 'library_controller.dart';

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
        startIndex: start,
        setlistName: setlistName,
        onOpened: library.settings.recordOpened,
      ),
    ),
  );
  for (final i in items.map((i) => i.path).toSet()) {
    await library.refreshEntry(i);
  }
}
