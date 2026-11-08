import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/ink/drawing_preset.dart';
import '../../core/ink/stroke.dart';
import 'ink_controller.dart';
import 'preset_editor.dart';
import 'tool_controller.dart';

/// Schmale Werkzeug-Palette am Seitenrand – dort, wo neben der Notenseite
/// ohnehin Platz ist. Während gezeichnet wird, wird sie fast durchsichtig,
/// damit sie nicht ablenkt.
class ToolPalette extends StatelessWidget {
  const ToolPalette({super.key, required this.tools, required this.ink, required this.page});

  final ToolController tools;
  final InkController ink;
  final int page;

  Future<void> _confirmClear(BuildContext context) async {
    if (!ink.pageHasAnnotations(page)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Seite leeren?'),
        content: Text('Alle Anmerkungen auf Seite $page werden entfernt. Mit „Rückgängig“ holst du sie zurück.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Leeren')),
        ],
      ),
    );
    if (ok == true) ink.clearPage(page);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    return ValueListenableBuilder<bool>(
      valueListenable: tools.isDrawing,
      builder: (context, drawing, child) =>
          AnimatedOpacity(duration: const Duration(milliseconds: 180), opacity: drawing ? 0.12 : 1, child: child),
      child: ListenableBuilder(
        listenable: Listenable.merge([tools, ink]),
        builder: (context, _) {
          final mode = tools.mode;
          return Material(
            elevation: 3,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            color: scheme.surface,
            child: Ink(
              width: 60,
              decoration: BoxDecoration(gradient: VoltiColors.barGradient(brightness)),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: 'Fertig (Esc)',
                      child: IconButton.filled(
                        onPressed: () => tools.setMode(ToolMode.read),
                        icon: const Icon(Icons.check),
                      ),
                    ),
                    const _Sep(),
                    for (final (i, p) in tools.presets.indexed)
                      _PresetButton(
                        preset: p,
                        selected: mode == ToolMode.draw && tools.current.id == p.id,
                        shortcut: i < 9 ? '${i + 1}' : null,
                        onTap: () => mode == ToolMode.draw && tools.current.id == p.id
                            ? showPresetEditor(context, tools, p)
                            : tools.select(p),
                        onLongPress: () => showPresetEditor(context, tools, p),
                      ),
                    _PaletteIcon(
                      icon: Icons.add,
                      tooltip: 'Neue Vorlage',
                      onTap: () => showPresetEditor(context, tools, tools.addPreset()),
                    ),
                    const _Sep(),
                    _PaletteIcon(
                      icon: Icons.auto_fix_normal,
                      tooltip: 'Radierer (E)',
                      selected: mode == ToolMode.eraser,
                      onTap: () => tools.setMode(ToolMode.eraser),
                    ),
                    if (mode == ToolMode.eraser)
                      for (final (i, r) in ToolController.eraserSizes.indexed)
                        _SizeDot(
                          tooltip: const ['Radierer klein', 'Radierer mittel', 'Radierer gross'][i],
                          diameter: 6.0 + i * 5,
                          selected: tools.eraserRadius == r,
                          onTap: () => tools.setEraserRadius(r),
                        ),
                    _PaletteIcon(
                      icon: Icons.text_fields,
                      tooltip: 'Text-Notiz (T)',
                      selected: mode == ToolMode.text,
                      onTap: () => tools.setMode(ToolMode.text),
                    ),
                    if (mode == ToolMode.text)
                      for (final (i, s) in ToolController.textSizes.indexed)
                        _SizeLetter(
                          tooltip: const ['Schrift klein', 'Schrift mittel', 'Schrift gross'][i],
                          fontSize: 11.0 + i * 4,
                          selected: tools.textSize == s,
                          onTap: () => tools.setTextSize(s),
                        ),
                    const _Sep(),
                    _PaletteIcon(
                      icon: Icons.undo,
                      tooltip: 'Rückgängig (Strg+Z)',
                      onTap: ink.canUndo ? ink.undo : null,
                    ),
                    _PaletteIcon(
                      icon: Icons.redo,
                      tooltip: 'Wiederholen (Strg+Y)',
                      onTap: ink.canRedo ? ink.redo : null,
                    ),
                    _PaletteIcon(
                      icon: Icons.delete_sweep_outlined,
                      tooltip: 'Seite leeren',
                      onTap: ink.pageHasAnnotations(page) ? () => _confirmClear(context) : null,
                    ),
                    const _Sep(),
                    _PaletteIcon(
                      icon: tools.paletteLeft ? Icons.keyboard_double_arrow_right : Icons.keyboard_double_arrow_left,
                      tooltip: 'Palette auf die andere Seite',
                      onTap: tools.togglePaletteSide,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) => Container(
    width: 28,
    height: 1,
    margin: const EdgeInsets.symmetric(vertical: 6),
    color: Theme.of(context).dividerColor,
  );
}

class _PaletteIcon extends StatelessWidget {
  const _PaletteIcon({required this.icon, required this.tooltip, this.onTap, this.selected = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      isSelected: selected,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: selected ? scheme.primaryContainer : null,
        foregroundColor: selected ? scheme.onPrimaryContainer : null,
      ),
    );
  }
}

/// Eine Stift-Vorlage: zeigt Farbe und Dicke. Nochmals antippen öffnet den Editor.
class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.preset,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    this.shortcut,
  });

  final DrawingPreset preset;
  final bool selected;
  final String? shortcut;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hl = preset.tool == InkTool.highlighter;
    final min = hl ? DrawingPreset.minMarkerWidth : DrawingPreset.minPenWidth;
    final max = hl ? DrawingPreset.maxMarkerWidth : DrawingPreset.maxPenWidth;
    final t = ((preset.width - min) / (max - min)).clamp(0.0, 1.0);
    final color = Color(preset.color);
    final isWhite = (preset.color & 0xFFFFFF) == 0xFFFFFF;
    final tip =
        '${presetLabel(preset)}${shortcut == null ? '' : ' (Taste $shortcut)'}'
        '${selected ? ' – nochmals tippen zum Bearbeiten' : ''}';
    return Tooltip(
      message: tip,
      child: InkResponse(
        onTap: onTap,
        onLongPress: onLongPress,
        radius: 24,
        child: Container(
          width: 44,
          height: 40,
          margin: const EdgeInsets.symmetric(vertical: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: hl
              ? Container(
                  width: 28,
                  height: 8 + 10 * t,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                )
              : Container(
                  width: 10 + 16 * t,
                  height: 10 + 16 * t,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: isWhite ? Border.all(color: scheme.outline) : null,
                  ),
                ),
        ),
      ),
    );
  }
}

class _SizeDot extends StatelessWidget {
  const _SizeDot({required this.tooltip, required this.diameter, required this.selected, required this.onTap});
  final String tooltip;
  final double diameter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 16,
        child: SizedBox(
          width: 40,
          height: 28,
          child: Center(
            child: Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? scheme.primary : null,
                border: Border.all(color: selected ? scheme.primary : scheme.outline, width: 1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SizeLetter extends StatelessWidget {
  const _SizeLetter({required this.tooltip, required this.fontSize, required this.selected, required this.onTap});
  final String tooltip;
  final double fontSize;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 16,
        child: SizedBox(
          width: 40,
          height: 28,
          child: Center(
            child: Text(
              'A',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
