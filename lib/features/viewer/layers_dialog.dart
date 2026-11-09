import 'package:flutter/material.dart';

import '../../core/ink/annotation_layer.dart';
import 'ink_controller.dart';

/// Öffnet die Ebenen eines Stücks: anlegen, umbenennen, ein-/ausblenden,
/// Reihenfolge ändern, zusammenführen, duplizieren, löschen.
Future<void> showLayersDialog(BuildContext context, InkController ink) => showDialog<void>(
  context: context,
  builder: (_) => _LayersDialog(ink: ink),
);

class _LayersDialog extends StatelessWidget {
  const _LayersDialog({required this.ink});
  final InkController ink;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Ebenen')),
          TextButton.icon(
            onPressed: () async {
              final name = await _askName(context, 'Neue Ebene', 'Ebene ${ink.layers.length + 1}');
              if (name != null) ink.addLayer(name);
            },
            icon: const Icon(Icons.add),
            label: const Text('Neue Ebene'),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: ListenableBuilder(
          listenable: ink,
          builder: (context, _) {
            // Oben in der Liste = oben auf der Seite.
            final shown = ink.layers.reversed.toList();
            final active = ink.activeLayer;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Gelten für dieses Stück, auf allen Seiten. Was du zeichnest, landet auf der markierten Ebene. '
                  'Am Griff ☰ ziehen ändert die Reihenfolge.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    buildDefaultDragHandles: false,
                    itemCount: shown.length,
                    // [to] ist schon die Position nach dem Herausnehmen.
                    onReorderItem: (from, to) => ink.moveLayer(shown[from].id, shown.length - 1 - to),
                    itemBuilder: (context, i) {
                      final l = shown[i];
                      return _LayerRow(
                        key: ValueKey(l.id),
                        ink: ink,
                        layer: l,
                        index: i,
                        active: l.id == active,
                        others: [
                          for (final o in shown)
                            if (o.id != l.id) o,
                        ],
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig'))],
    );
  }
}

class _LayerRow extends StatelessWidget {
  const _LayerRow({
    super.key,
    required this.ink,
    required this.layer,
    required this.index,
    required this.active,
    required this.others,
  });

  final InkController ink;
  final AnnotationLayer layer;
  final int index;
  final bool active;
  final List<AnnotationLayer> others;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = ink.countOnLayer(layer.id);
    return Material(
      color: active ? scheme.primaryContainer.withValues(alpha: 0.6) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 4, right: 0),
        onTap: () => ink.activeLayer = layer.id,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle)),
              ),
            ),
            Icon(
              active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: active ? scheme.primary : scheme.outline,
              size: 20,
            ),
          ],
        ),
        title: Text(
          layer.name,
          style: TextStyle(
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: layer.visible ? null : scheme.onSurfaceVariant,
          ),
        ),
        subtitle: Text(count == 1 ? '1 Element' : '$count Elemente'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: layer.visible ? 'Ausblenden' : 'Einblenden',
              icon: Icon(layer.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => ink.setLayerVisible(layer.id, !layer.visible),
            ),
            PopupMenuButton<String>(
              tooltip: 'Mehr',
              onSelected: (v) => _action(context, v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rename', child: Text('Umbenennen …')),
                const PopupMenuItem(value: 'duplicate', child: Text('Duplizieren')),
                if (!layer.isDefault && others.isNotEmpty)
                  const PopupMenuItem(value: 'merge', child: Text('Zusammenführen mit …')),
                if (!layer.isDefault) const PopupMenuItem(value: 'delete', child: Text('Löschen …')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _action(BuildContext context, String v) async {
    switch (v) {
      case 'rename':
        final name = await _askName(context, 'Ebene umbenennen', layer.name);
        if (name != null) ink.renameLayer(layer.id, name);
      case 'duplicate':
        ink.duplicateLayer(layer.id);
      case 'merge':
        final into = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text('«${layer.name}» zusammenführen mit'),
            children: [
              for (final o in others)
                SimpleDialogOption(onPressed: () => Navigator.of(context).pop(o.id), child: Text(o.name)),
            ],
          ),
        );
        if (into != null) ink.mergeLayer(layer.id, into);
      case 'delete':
        final count = ink.countOnLayer(layer.id);
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('«${layer.name}» löschen?'),
            content: Text(
              count == 0
                  ? 'Die Ebene ist leer.'
                  : 'Damit werden auch ${count == 1 ? 'das Element' : 'die $count Elemente'} darauf gelöscht '
                        '(auf allen Seiten). Mit «Rückgängig» lassen sie sich zurückholen.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Löschen')),
            ],
          ),
        );
        if (ok == true) ink.deleteLayer(layer.id);
    }
  }
}

Future<String?> _askName(BuildContext context, String title, String initial) {
  final text = TextEditingController(text: initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: text,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'z. B. Fingersätze, Dynamik, Probe'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.of(context).pop(text.text), child: const Text('OK')),
      ],
    ),
  ).whenComplete(text.dispose);
}

/// Name der aktiven Ebene (für Hinweise), null wenn es nur eine gibt.
String? activeLayerLabel(InkController ink) {
  final layers = ink.layers;
  if (layers.length < 2) return null;
  final id = ink.activeLayer;
  return layers.firstWhere((l) => l.id == id, orElse: () => layers.first).name;
}

/// Kleine Zeile "Ebene: …" für Werkzeug-Fenster; antippen öffnet die Ebenen.
class ActiveLayerChip extends StatelessWidget {
  const ActiveLayerChip({super.key, required this.ink});
  final InkController ink;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ink,
    builder: (context, _) {
      final name = activeLayerLabel(ink);
      if (name == null) return const SizedBox.shrink();
      final scheme = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => showLayersDialog(context, ink),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(Icons.layers_outlined, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Ebene: $name',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.primary),
                  ),
                ),
                Icon(Icons.expand_more, size: 16, color: scheme.primary),
              ],
            ),
          ),
        ),
      );
    },
  );
}
