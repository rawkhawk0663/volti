import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/ink/annotation_layer.dart';
import '../../core/ink/layer_drop.dart';
import 'ink_controller.dart';
import 'tool_controller.dart';
import '../../app/l10n.dart';

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

  /// Fläche jeder Zeile (für die Ablage beim Ziehen).
  final Map<String, RenderBox> _rowBoxes = {};

  /// Sichtbare Zeilen: oben zuerst, Ebenen zugeklappter Gruppen fehlen.
  List<({AnnotationLayer layer, int depth})> _rows() => [
    for (final r in ink.annotations.outline())
      if (r.depth == 0 || !_collapsed.contains(r.layer.parent)) r,
  ];

  /// Zeilen für die Ablage-Berechnung (alle, auch in zugeklappten Gruppen).
  List<LayerRow> _allRows() => [
    for (final r in ink.annotations.outline())
      (id: r.layer.id, isGroup: r.layer.isGroup, group: r.depth == 1 ? r.layer.parent : null),
  ];

  /// Gerade gezogene Ebene und wohin sie fallen würde (für die Vorschau).
  String? _dragging;
  LayerDrop? _drop;

  void _hover(String target, Offset local, Size size) {
    final moved = _dragging;
    if (moved == null) return;
    final drop = moved == target
        ? null
        : planLayerDrop(_allRows(), moved, target, lowerHalf: local.dy > size.height / 2, outdent: local.dx < 40);
    if (drop != _drop) setState(() => _drop = drop);
  }

  void _accept() {
    final moved = _dragging, drop = _drop;
    setState(() {
      _dragging = null;
      _drop = null;
    });
    if (moved == null || drop == null) return;
    if (drop.group != null) _collapsed.remove(drop.group);
    ink.arrangeLayers(applyLayerDrop(_allRows(), moved, drop));
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
            if (ink.scope != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  tr(
                    'Neue Ebenen gelten nur in dieser Setlist. Ebenen mit dem Bibliotheks-Zeichen gehören zum Song '
                        'und sind überall sichtbar.',
                    'New layers apply only to this setlist. Layers with the library sign belong to the song '
                        'and are visible everywhere.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () async {
                    final name = await askName(
                      context,
                      tr('Neue Ebene', 'New layer'),
                      tr('Ebene ${ink.drawableLayers.length + 1}', 'Layer ${ink.drawableLayers.length + 1}'),
                    );
                    if (name != null) ink.addLayer(name);
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(tr('Ebene', 'Layer')),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final name = await askName(context, tr('Neue Gruppe', 'New group'), tr('Gruppe', 'Group'));
                    if (name != null) ink.addGroup(name);
                  },
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: Text(tr('Gruppe', 'Group')),
                ),
              ],
            ),
            for (final r in rows)
              DragTarget<String>(
                key: ValueKey(r.layer.id),
                onWillAcceptWithDetails: (_) => true,
                onMove: (d) {
                  final rowBox = _rowBoxes[r.layer.id];
                  if (rowBox == null || !rowBox.attached) return;
                  _hover(r.layer.id, rowBox.globalToLocal(d.offset), rowBox.size);
                },
                onAcceptWithDetails: (_) => _accept(),
                builder: (context, _, _) => _Row(
                  ink: ink,
                  layer: r.layer,
                  depth: r.depth,
                  active: r.layer.id == active,
                  collapsed: _collapsed.contains(r.layer.id),
                  dragging: _dragging == r.layer.id,
                  // Vorschau: Linie über/unter der Zeile, eingerückt, wenn die
                  // Ebene in eine Gruppe kommt.
                  dropLine: _drop?.target == r.layer.id ? (after: _drop!.after, indented: _drop!.group != null) : null,
                  onBox: (b) => _rowBoxes[r.layer.id] = b,
                  onDragStart: () => setState(() => _dragging = r.layer.id),
                  onDragEnd: () {
                    if (_dragging != null) {
                      setState(() {
                        _dragging = null;
                        _drop = null;
                      });
                    }
                  },
                  onToggle: () => setState(
                    () => _collapsed.contains(r.layer.id) ? _collapsed.remove(r.layer.id) : _collapsed.add(r.layer.id),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Text(
              tr(
                'Antippen: darauf zeichnen. Am Griff ziehen: Reihenfolge ändern, auch in eine Gruppe hinein. '
                    'Ebenen gelten für das ganze Stück.',
                'Tap: draw on it. Drag the handle: change the order, also into a group. '
                    'Layers apply to the whole piece.',
              ),
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
    required this.ink,
    required this.layer,
    required this.depth,
    required this.active,
    required this.collapsed,
    required this.onToggle,
    required this.dragging,
    required this.dropLine,
    required this.onBox,
    required this.onDragStart,
    required this.onDragEnd,
  });

  final InkController ink;
  final AnnotationLayer layer;
  final int depth;
  final bool active;
  final bool collapsed;
  final VoidCallback onToggle;
  final bool dragging;
  final ({bool after, bool indented})? dropLine;
  final ValueChanged<RenderBox> onBox;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = ink.annotations.isLayerShown(layer.id);
    final count = ink.countOnLayer(layer.id);
    final groups = [
      for (final l in ink.layers.reversed)
        if (l.isGroup) l,
    ];
    final line = dropLine;
    Widget indicator(bool show) => SizedBox(
      height: 3,
      child: show
          ? Padding(
              padding: EdgeInsets.only(left: line!.indented ? 28 : 0),
              child: DecoratedBox(
                decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(2)),
              ),
            )
          : null,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        indicator(line != null && !line.after),
        _BoxReporter(
          onBox: onBox,
          child: Opacity(opacity: dragging ? 0.4 : 1, child: _rowBody(context, scheme, shown, count, groups)),
        ),
        indicator(line != null && line.after),
      ],
    );
  }

  Widget _rowBody(BuildContext context, ColorScheme scheme, bool shown, int count, List<AnnotationLayer> groups) {
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
                Draggable<String>(
                  data: layer.id,
                  dragAnchorStrategy: pointerDragAnchorStrategy,
                  onDragStarted: onDragStart,
                  onDragEnd: (_) => onDragEnd(),
                  onDraggableCanceled: (_, _) => onDragEnd(),
                  feedback: Material(
                    elevation: 0,
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(layer.isGroup ? Icons.folder_outlined : Icons.layers_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(layer.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 10),
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
                // In einer Setlist: wohin gehört die Ebene?
                if (ink.scope != null)
                  Tooltip(
                    message: layer.scope != null
                        ? tr('Nur in dieser Setlist', 'Only in this setlist')
                        : tr(
                            'Gehört zum Song – in der Bibliothek und allen Setlists',
                            'Belongs to the song – in the library and all setlists',
                          ),
                    child: Icon(
                      layer.scope != null ? Icons.queue_music : Icons.library_music_outlined,
                      size: 16,
                      color: layer.scope != null ? scheme.primary : scheme.outline,
                    ),
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: layer.visible ? tr('Ausblenden', 'Hide') : tr('Einblenden', 'Show'),
                  icon: Icon(layer.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                  onPressed: () => ink.setLayerVisible(layer.id, !layer.visible),
                ),
                PopupMenuButton<VoidCallback>(
                  tooltip: tr('Mehr', 'More'),
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  onSelected: (a) => a(),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: () async {
                        final name = await askName(
                          context,
                          layer.isGroup
                              ? tr('Gruppe umbenennen', 'Rename group')
                              : tr('Ebene umbenennen', 'Rename layer'),
                          layer.name,
                        );
                        if (name != null) ink.renameLayer(layer.id, name);
                      },
                      child: Text(tr('Umbenennen …', 'Rename …')),
                    ),
                    if (layer.isGroup) ...[
                      PopupMenuItem(
                        value: () async {
                          final name = await askName(
                            context,
                            tr('Neue Ebene in «${layer.name}»', 'New layer in «${layer.name}»'),
                            tr('Ebene ${ink.drawableLayers.length + 1}', 'Layer ${ink.drawableLayers.length + 1}'),
                          );
                          if (name != null) ink.addLayer(name, group: layer.id);
                        },
                        child: Text(tr('Neue Ebene darin …', 'New layer inside …')),
                      ),
                      PopupMenuItem(
                        value: () => ink.dissolveGroup(layer.id),
                        child: Text(tr('Gruppe auflösen', 'Ungroup')),
                      ),
                    ] else ...[
                      PopupMenuItem(
                        value: () => ink.duplicateLayer(layer.id),
                        child: Text(tr('Duplizieren', 'Duplicate')),
                      ),
                      for (final g in groups)
                        if (g.id != layer.parent)
                          PopupMenuItem(
                            value: () => ink.moveLayerToGroup(layer.id, g.id),
                            child: Text(tr('In Gruppe «${g.name}»', 'Into group «${g.name}»')),
                          ),
                      if (layer.parent != null && ink.annotations.groupOf(layer) != null)
                        PopupMenuItem(
                          value: () => ink.moveLayerToGroup(layer.id, null),
                          child: Text(tr('Aus der Gruppe nehmen', 'Take out of the group')),
                        ),
                    ],
                    if (!layer.isDefault)
                      PopupMenuItem(value: () => _confirmDelete(context), child: Text(tr('Löschen …', 'Delete …'))),
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
    final what = layer.isGroup
        ? tr('Die Gruppe und alle Ebenen darin', 'The group and all layers in it')
        : tr('Die Ebene', 'The layer');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('«${layer.name}» löschen?', 'Delete «${layer.name}»?')),
        content: Text(
          count == 0
              ? tr(
                  '$what werden gelöscht. Mit «Rückgängig» lässt sich das zurückholen.',
                  '$what will be deleted. You can bring it back with «Undo».',
                )
              : tr(
                  '$what werden gelöscht, mitsamt ${count == 1 ? 'dem Element' : 'den $count Elementen'} darauf '
                      '(auf allen Seiten). Mit «Rückgängig» lässt sich alles zurückholen.',
                  '$what will be deleted, together with ${count == 1 ? 'the element' : 'the $count elements'} on it '
                      '(on all pages). You can bring everything back with «Undo».',
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(tr('Löschen', 'Delete'))),
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
        decoration: InputDecoration(
          hintText: tr('z. B. Fingersätze, Dynamik, Probe', 'e.g. fingerings, dynamics, rehearsal'),
        ),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Abbrechen', 'Cancel'))),
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
                    tr('Ebene: $name', 'Layer: $name'),
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

/// Meldet die Fläche einer Zeile (für die Ablage beim Ziehen).
class _BoxReporter extends SingleChildRenderObjectWidget {
  const _BoxReporter({required this.onBox, required super.child});
  final ValueChanged<RenderBox> onBox;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBoxReporter(onBox);

  @override
  void updateRenderObject(BuildContext context, _RenderBoxReporter renderObject) => renderObject.onBox = onBox;
}

class _RenderBoxReporter extends RenderProxyBox {
  _RenderBoxReporter(this.onBox);
  ValueChanged<RenderBox> onBox;

  @override
  void performLayout() {
    super.performLayout();
    onBox(this);
  }
}
