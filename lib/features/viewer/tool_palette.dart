import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'ink_controller.dart';
import 'layers_panel.dart';
import 'tool_controller.dart';
import 'tool_popover.dart';

/// Werkzeuge beim Bearbeiten: eine feste, schmale Leiste am Seitenrand und
/// daneben das Einstellungsfenster des aktiven Werkzeugs.
///
/// * Werkzeug antippen → wählen, das Fenster erscheint.
/// * Aktives Werkzeug nochmals antippen → abwählen, das Fenster verschwindet.
/// * Das Fenster lässt sich frei verschieben; beim Werkzeugwechsel erscheint
///   das neue Fenster an derselben Stelle.
///
/// Füllt den ganzen Bildschirm, fängt aber nur Berührungen auf Leiste und
/// Fenster ab – alles andere geht an die Notenseite darunter.
class ToolOverlay extends StatefulWidget {
  const ToolOverlay({super.key, required this.tools, required this.ink, required this.page});

  final ToolController tools;
  final InkController ink;
  final int page;

  @override
  State<ToolOverlay> createState() => _ToolOverlayState();
}

class _ToolOverlayState extends State<ToolOverlay> {
  static const _barWidth = 60.0, _margin = 10.0;

  ToolController get tools => widget.tools;

  /// Position während des Ziehens (danach in tools.popoverOffset gemerkt).
  final _dragOffset = ValueNotifier<Offset?>(null);

  void _drag(Offset delta, Size screen) {
    final from = _dragOffset.value ?? tools.popoverOffset ?? _defaultOffset(screen);
    final to = _clamp(from + delta, screen);
    _dragOffset.value = to;
    tools.popoverOffset = to;
  }

  @override
  void dispose() {
    _dragOffset.dispose();
    super.dispose();
  }

  Offset _defaultOffset(Size screen) {
    final x = tools.paletteLeft
        ? _margin + _barWidth + 12
        : screen.width - _margin - _barWidth - 12 - ToolPopover.width;
    return Offset(x, 64);
  }

  /// Fenster innerhalb des Bildschirms halten.
  Offset _clamp(Offset o, Size screen) => Offset(
    o.dx.clamp(0, (screen.width - ToolPopover.width).clamp(0, double.infinity)),
    o.dy.clamp(0, (screen.height - 120).clamp(0, double.infinity)),
  );

  Future<void> _confirmClear() async {
    final ink = widget.ink, page = widget.page;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = constraints.biggest;
        return ListenableBuilder(
          listenable: Listenable.merge([tools, widget.ink]),
          builder: (context, _) {
            final mode = tools.mode;
            final hasPopover = tools.layersOpen || (mode != ToolMode.read && mode != ToolMode.none);
            final offset = _clamp(tools.popoverOffset ?? _defaultOffset(screen), screen);
            return Stack(
              children: [
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: tools.paletteLeft ? _margin : null,
                  right: tools.paletteLeft ? null : _margin,
                  child: Center(child: RepaintBoundary(child: _buildBar(context))),
                ),
                if (hasPopover)
                  // Beim Ziehen ändert sich nur die Position (_dragOffset) – der
                  // Fensterinhalt wird dabei nicht jedes Mal neu aufgebaut.
                  ValueListenableBuilder<Offset?>(
                    valueListenable: _dragOffset,
                    child: RepaintBoundary(
                      child: ToolPopover(
                        key: ValueKey(tools.layersOpen ? 'layers' : mode),
                        tools: tools,
                        ink: widget.ink,
                        page: widget.page,
                        onDrag: (d) => _drag(d, screen),
                      ),
                    ),
                    builder: (context, dragged, child) {
                      // dragged löst nur das Neuzeichnen aus; massgeblich ist die gemerkte Position.
                      final o = _clamp(tools.popoverOffset ?? offset, screen);
                      return Positioned(
                        left: o.dx,
                        top: o.dy,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: (screen.height - o.dy - 12).clamp(160, 640)),
                          child: child,
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = widget.ink;
    final mode = tools.mode;
    Widget tool(ToolMode m, IconData icon, String tip, {Color? dot}) =>
        _BarButton(icon: icon, tooltip: tip, selected: mode == m, dot: dot, onTap: () => tools.tapTool(m));
    return Material(
      // Kein Schatten: Er müsste bei jedem Bild beim Zeichnen mitgemalt werden.
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      color: scheme.surface,
      child: Ink(
        width: _barWidth,
        decoration: BoxDecoration(gradient: VoltiColors.barGradient(Theme.of(context).brightness)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: 'Fertig (Esc)',
                child: IconButton.filled(onPressed: tools.finishEditing, icon: const Icon(Icons.check)),
              ),
              const _Sep(),
              tool(ToolMode.pen, Icons.edit, 'Stift (P)', dot: Color(tools.pen.color | 0xFF000000)),
              tool(
                ToolMode.highlighter,
                Icons.border_color,
                'Textmarker (H)',
                dot: Color(tools.highlighter.color | 0xFF000000),
              ),
              tool(ToolMode.eraser, Icons.auto_fix_normal, 'Radierer (E)'),
              tool(ToolMode.lasso, Icons.highlight_alt, 'Auswählen (A)'),
              tool(ToolMode.text, Icons.text_fields, 'Text (T)'),
              tool(ToolMode.stamp, Icons.music_note, 'Stempel (S)'),
              tool(ToolMode.shape, Icons.category_outlined, 'Formen (F)'),
              tool(ToolMode.link, Icons.turn_right, 'Sprungmarke (J)'),
              _BarButton(
                icon: Icons.layers_outlined,
                tooltip: activeLayerLabel(ink) == null ? 'Ebenen' : 'Ebenen (aktiv: ${activeLayerLabel(ink)})',
                selected: tools.layersOpen,
                onTap: tools.toggleLayers,
              ),
              _BarButton(
                icon: Icons.straighten,
                tooltip: 'Lineal (L)',
                selected: tools.rulerVisible,
                onTap: tools.toggleRuler,
              ),
              const _Sep(),
              _BarButton(icon: Icons.undo, tooltip: 'Rückgängig (Strg+Z)', onTap: ink.canUndo ? ink.undo : null),
              _BarButton(icon: Icons.redo, tooltip: 'Wiederholen (Strg+Y)', onTap: ink.canRedo ? ink.redo : null),
              _BarButton(
                icon: Icons.delete_sweep_outlined,
                tooltip: 'Seite leeren',
                onTap: ink.pageHasAnnotations(widget.page) ? _confirmClear : null,
              ),
              const _Sep(),
              _BarButton(
                icon: tools.paletteLeft ? Icons.keyboard_double_arrow_right : Icons.keyboard_double_arrow_left,
                tooltip: 'Leiste auf die andere Seite',
                onTap: tools.togglePaletteSide,
              ),
            ],
          ),
        ),
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

/// Knopf in der Leiste; [dot] zeigt die aktuelle Farbe des Werkzeugs.
class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.tooltip, this.onTap, this.selected = false, this.dot});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool selected;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final button = IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      isSelected: selected,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: selected ? scheme.primaryContainer : null,
        foregroundColor: selected ? scheme.onPrimaryContainer : null,
      ),
    );
    if (dot == null) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          right: 6,
          bottom: 6,
          child: IgnorePointer(
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
