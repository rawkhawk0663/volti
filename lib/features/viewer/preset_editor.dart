import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/ink/drawing_preset.dart';
import '../../core/ink/stroke.dart';
import 'ink_layer.dart';
import 'tool_controller.dart';

/// Farben für Stifte (deckend) und Textmarker (hell).
const _penColors = [
  0xFF1B1B1B, 0xFF616161, 0xFFC62828, 0xFFEF6C00, 0xFFF9A825, 0xFF2E7D32, //
  0xFF1A8070, 0xFF1565C0, 0xFF6A1B9A, 0xFFAD1457, 0xFF6D4C41, 0xFFFFFFFF,
];
const _markerColors = [0xFFFFE066, 0xFF77DD99, 0xFF7FD3F7, 0xFFFF9EC4, 0xFFFFB74D, 0xFFC5A3FF];

/// Kurzer Name einer Vorlage für Tooltips, z. B. "Stift · fein".
String presetLabel(DrawingPreset p) {
  final kind = p.tool == InkTool.highlighter
      ? 'Textmarker'
      : (p.color & 0xFFFFFF) == 0xFFFFFF
      ? 'Abdecken'
      : 'Stift';
  final range = p.tool == InkTool.highlighter
      ? (DrawingPreset.maxMarkerWidth - DrawingPreset.minMarkerWidth)
      : (DrawingPreset.maxPenWidth - DrawingPreset.minPenWidth);
  final min = p.tool == InkTool.highlighter ? DrawingPreset.minMarkerWidth : DrawingPreset.minPenWidth;
  final t = ((p.width - min) / range).clamp(0.0, 1.0);
  final thickness = t < 0.2 ? 'fein' : (t < 0.5 ? 'mittel' : 'dick');
  return '$kind · $thickness';
}

/// Öffnet den Editor für eine Stift-Vorlage. Änderungen werden beim
/// Schliessen übernommen.
Future<void> showPresetEditor(BuildContext context, ToolController tools, DrawingPreset preset) async {
  var draft = preset;
  var deleted = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final hl = draft.tool == InkTool.highlighter;
        final colors = hl ? _markerColors : _penColors;
        final alpha = (draft.color >> 24) / 255.0;
        int withAlpha(int rgb, double a) => ((a * 255).round() << 24) | (rgb & 0xFFFFFF);
        return AlertDialog(
          title: const Text('Stift-Vorlage'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<InkTool>(
                    segments: const [
                      ButtonSegment(value: InkTool.pen, icon: Icon(Icons.edit), label: Text('Stift')),
                      ButtonSegment(
                        value: InkTool.highlighter,
                        icon: Icon(Icons.border_color),
                        label: Text('Textmarker'),
                      ),
                    ],
                    selected: {draft.tool},
                    onSelectionChanged: (v) => setState(() {
                      final tool = v.first;
                      draft = tool == InkTool.highlighter
                          ? draft.copyWith(tool: tool, color: withAlpha(_markerColors.first, 0.6), width: 0.014)
                          : draft.copyWith(tool: tool, color: _penColors.first, width: 0.003);
                    }),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Theme.of(ctx).dividerColor),
                    ),
                    child: CustomPaint(painter: _PreviewPainter(draft)),
                  ),
                  const SizedBox(height: 16),
                  Text('Farbe', style: Theme.of(ctx).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in colors)
                        _Swatch(
                          color: Color(c),
                          selected: (draft.color & 0xFFFFFF) == (c & 0xFFFFFF),
                          onTap: () => setState(() => draft = draft.copyWith(color: withAlpha(c, alpha))),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Breite', style: Theme.of(ctx).textTheme.labelLarge),
                  Slider(
                    min: hl ? DrawingPreset.minMarkerWidth : DrawingPreset.minPenWidth,
                    max: hl ? DrawingPreset.maxMarkerWidth : DrawingPreset.maxPenWidth,
                    value: draft.width.clamp(
                      hl ? DrawingPreset.minMarkerWidth : DrawingPreset.minPenWidth,
                      hl ? DrawingPreset.maxMarkerWidth : DrawingPreset.maxPenWidth,
                    ),
                    onChanged: (v) => setState(() => draft = draft.copyWith(width: v)),
                  ),
                  Text('Deckkraft', style: Theme.of(ctx).textTheme.labelLarge),
                  Slider(
                    min: 0.2,
                    max: 1,
                    value: alpha.clamp(0.2, 1),
                    onChanged: (v) => setState(() => draft = draft.copyWith(color: withAlpha(draft.color, v))),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (tools.presets.length > 1)
              TextButton.icon(
                onPressed: () {
                  deleted = true;
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Löschen'),
              ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fertig')),
          ],
        );
      },
    ),
  );
  if (deleted) {
    tools.deletePreset(preset);
  } else if (draft.color != preset.color || draft.width != preset.width || draft.tool != preset.tool) {
    tools.updatePreset(draft);
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkResponse(
      onTap: onTap,
      radius: 20,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 3 : 1,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
        ),
      ),
    );
  }
}

/// Probestrich im Editor: eine kleine Welle mit an- und abschwellendem Druck.
class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.preset);
  final DrawingPreset preset;

  @override
  void paint(Canvas canvas, Size size) {
    // Notenlinien als Hintergrund, damit man sieht, wie es auf Noten wirkt.
    final line = Paint()
      ..color = const Color(0xFF9E9E9E)
      ..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      final y = size.height * 0.3 + i * size.height * 0.1;
      canvas.drawLine(Offset(8, y), Offset(size.width - 8, y), line);
    }
    final pts = <InkPoint>[
      for (var i = 0; i <= 40; i++)
        InkPoint(
          0.08 + 0.84 * i / 40,
          0.5 + 0.18 * math.sin(i / 40 * 6.28) * (size.width / size.height) / 5,
          0.3 + 0.6 * math.sin(i / 40 * 3.14),
        ),
    ];
    // Breite ist relativ zur Seitenbreite; die Vorschau zeigt eine Seite von ~600 px.
    final scale = 600 / size.width;
    paintStroke(canvas, size, preset.tool, Color(preset.color), preset.width * scale, pts);
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.preset != preset;
}
