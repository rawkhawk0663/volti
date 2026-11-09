import 'package:flutter/material.dart';

import '../../core/ink/annotation_layer.dart';
import 'ink_controller.dart';
import 'tool_controller.dart';

/// Ebenen eines Stücks – im Werkzeug-Fenster, am selben Ort wie die
/// Werkzeug-Einstellungen. Anlegen, Gruppen, ein-/ausblenden, ordnen,
/// umbenennen, duplizieren, löschen. Alles ausser Ein-/Ausblenden lässt sich
/// rückgängig machen.
class LayersPanel extends StatefulWidget {
  const LayersPanel({super.key, required this.ink});
  final InkController ink;

  @override
  State<LayersPanel> createState() => _LayersPanelState();
}

class _LayersPanelState extends State<LayersPanel> {
  InkController get ink => widget.ink;

  /// Zugeklappte Gruppen (nur auf diesem Gerät, nur solange das Fenster lebt).
  final Set<String> _collapsed = {};

  /// Sichtbare Zeilen: oben zuerst, Ebenen zugeklappter Gruppen fehlen.
  List<({AnnotationLayer layer, int depth})> _rows() => [
    for (final r in ink.annotations.outline())
      if (r.depth == 0 || !_collapsed.contains(r.layer.parent)) r,
  ];

  /// Neue Anordnung nach dem Ziehen. Eine Ebene kommt in die Gruppe, wenn sie
  /// direkt unter einem Gruppen-Kopf oder einer Ebene dieser Gruppe landet.
  void _reorder(int from, int to) {
    final rows = _rows();
    final moved = rows[from];
    final all = ink.annotations.outline();
    // Gezogene Gruppe nimmt ihre (auch zugeklappten) Ebenen mit.
    final block = [
      for (final r in all)
        if (r.layer.id == moved.layer.id || (moved.layer.isGroup && r.depth == 1 && r.layer.parent == moved.layer.id))
          r,
    ];
    final rest = [
      for (final r in rows)
        if (!block.any((b) => b.layer.id == r.layer.id)) r,
    ];
    // [to] zählt in [rows] ohne das gezogene Element; ausgeblendete
    // Gruppen-Ebenen des Blocks davor herausrechnen.
    var at = to;
    for (var i = 0; i < to && i < rows.length; i++) {
      if (i != from && block.any((b) => b.layer.id == rows[i].layer.id)) at--;
    }
    at = at.clamp(0, rest.length);
    String? parent;
    if (!moved.layer.isGroup && at > 0) {
      final above = rest[at - 1].layer;
      parent = above.isGroup ? above.id : ink.annotations.groupOf(above)?.id;
    }
    if (moved.layer.isGroup) {
      // Gruppen nur zwischen oberste Einträge setzen, nicht mitten in eine Gruppe.
      while (at > 0 && at < rest.length && rest[at].depth == 1) {
        at++;
      }
    }
    final newRows = [...rest]..insertAll(at, block);
    // Zugeklappte Ebenen wieder hinter ihren Gruppen-Kopf setzen.
    final full = <({AnnotationLayer layer, int depth})>[];
    for (final r in newRows) {
      if (full.any((f) => f.layer.id == r.layer.id)) continue;
      full.add(r);
      if (r.layer.isGroup && _collapsed.contains(r.layer.id)) {
        for (final c in all) {
          if (c.depth == 1 && c.layer.parent == r.layer.id && !full.any((f) => f.layer.id == c.layer.id)) full.add(c);
        }
      }
    }
    ink.arrangeLayers([
      for (final r in full)
        (
          id: r.layer.id,
          parent: r.layer.id == moved.layer.id
              ? parent
              : (r.layer.isGroup ? null : ink.annotations.groupOf(r.layer)?.id),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: ink,
      builder: (context, _) {
        final rows = _rows();
        final active = ink.activeLayer;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () async {
                    final name = await askName(context, 'Neue Ebene', 'Ebene ${ink.drawableLayers.length + 1}');
                    if (name != null) ink.addLayer(name);
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ebene'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final name = await askName(context, 'Neue Gruppe', 'Gruppe');
                    if (name != null) ink.addGroup(name);
                  },
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: const Text('Gruppe'),
                ),
              ],
            ),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: rows.length,
              onReorderItem: _reorder,
              itemBuilder: (context, i) {
                final r = rows[i];
                return _Row(
                  key: ValueKey(r.layer.id),
                  ink: ink,
                  layer: r.layer,
                  depth: r.depth,
                  index: i,
                  active: r.layer.id == active,
                  collapsed: _collapsed.contains(r.layer.id),
                  onToggle: () => setState(
                    () => _collapsed.contains(r.layer.id) ? _collapsed.remove(r.layer.id) : _collapsed.add(r.layer.id),
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
            Text(
              'Antippen: darauf zeichnen. Am Griff ziehen: Reihenfolge ändern, auch in eine Gruppe hinein. '
              'Ebenen gelten für das ganze Stück.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.ink,
    required this.layer,
    required this.depth,
    required this.index,
    required this.active,
    required this.collapsed,
    required this.onToggle,
  });

  final InkController ink;
  final AnnotationLayer layer;
  final int depth;
  final int index;
  final bool active;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = ink.annotations.isLayerShown(layer.id);
    final count = ink.countOnLayer(layer.id);
    final groups = [
      for (final l in ink.layers.reversed)
        if (l.isGroup) l,
    ];
    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0, bottom: 2),
      child: Material(
        color: active ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: layer.isGroup ? onToggle : () => ink.activeLayer = layer.id,
          child: SizedBox(
            height: 42,
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.drag_indicator, size: 18),
                    ),
                  ),
                ),
                if (layer.isGroup)
                  Icon(collapsed ? Icons.folder_outlined : Icons.folder_open_outlined, size: 18, color: scheme.primary)
                else
                  Icon(
                    active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 16,
                    color: active ? scheme.primary : scheme.outline,
                  ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    count == 0 ? layer.name : '${layer.name}  ·  $count',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: active || layer.isGroup ? FontWeight.w600 : FontWeight.w400,
                      color: shown ? null : scheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: layer.visible ? 'Ausblenden' : 'Einblenden',
                  icon: Icon(layer.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                  onPressed: () => ink.setLayerVisible(layer.id, !layer.visible),
                ),
                PopupMenuButton<VoidCallback>(
                  tooltip: 'Mehr',
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  onSelected: (a) => a(),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: () async {
                        final name = await askName(
                          context,
                          layer.isGroup ? 'Gruppe umbenennen' : 'Ebene umbenennen',
                          layer.name,
                        );
                        if (name != null) ink.renameLayer(layer.id, name);
                      },
                      child: const Text('Umbenennen …'),
                    ),
                    if (layer.isGroup) ...[
                      PopupMenuItem(
                        value: () async {
                          final name = await askName(
                            context,
                            'Neue Ebene in «${layer.name}»',
                            'Ebene ${ink.drawableLayers.length + 1}',
                          );
                          if (name != null) ink.addLayer(name, group: layer.id);
                        },
                        child: const Text('Neue Ebene darin …'),
                      ),
                      PopupMenuItem(value: () => ink.dissolveGroup(layer.id), child: const Text('Gruppe auflösen')),
                    ] else ...[
                      PopupMenuItem(value: () => ink.duplicateLayer(layer.id), child: const Text('Duplizieren')),
                      for (final g in groups)
                        if (g.id != layer.parent)
                          PopupMenuItem(
                            value: () => ink.moveLayerToGroup(layer.id, g.id),
                            child: Text('In Gruppe «${g.name}»'),
                          ),
                      if (layer.parent != null && ink.annotations.groupOf(layer) != null)
                        PopupMenuItem(
                          value: () => ink.moveLayerToGroup(layer.id, null),
                          child: const Text('Aus der Gruppe nehmen'),
                        ),
                    ],
                    if (!layer.isDefault)
                      PopupMenuItem(value: () => _confirmDelete(context), child: const Text('Löschen …')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final count = ink.countOnLayer(layer.id);
    final what = layer.isGroup ? 'Die Gruppe und alle Ebenen darin' : 'Die Ebene';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('«${layer.name}» löschen?'),
        content: Text(
          count == 0
              ? '$what werden gelöscht. Mit «Rückgängig» lässt sich das zurückholen.'
              : '$what werden gelöscht, mitsamt ${count == 1 ? 'dem Element' : 'den $count Elementen'} darauf '
                    '(auf allen Seiten). Mit «Rückgängig» lässt sich alles zurückholen.',
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

Future<String?> askName(BuildContext context, String title, String initial) {
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
  final layers = ink.drawableLayers;
  if (layers.length < 2) return null;
  final id = ink.activeLayer;
  final l = layers.firstWhere((l) => l.id == id, orElse: () => layers.first);
  final g = ink.annotations.groupOf(l);
  return g == null ? l.name : '${g.name} › ${l.name}';
}

/// Kleine Zeile "Ebene: …" für Werkzeug-Fenster; antippen öffnet die Ebenen.
class ActiveLayerChip extends StatelessWidget {
  const ActiveLayerChip({super.key, required this.ink, required this.tools});
  final InkController ink;
  final ToolController tools;

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
          onTap: tools.openLayers,
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
                Icon(Icons.chevron_right, size: 16, color: scheme.primary),
              ],
            ),
          ),
        ),
      );
    },
  );
}
