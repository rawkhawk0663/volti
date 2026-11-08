import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/ink/stroke.dart';
import '../../core/ink/text_note.dart';
import '../../core/ink/tool_settings.dart';
import 'ink_layer.dart';
import 'tool_controller.dart';

/// Farben für Stift und Text (deckend) und Textmarker (hell).
const penColors = [
  0xFF1B1B1B, 0xFF616161, 0xFFC62828, 0xFFEF6C00, 0xFFF9A825, 0xFF2E7D32, //
  0xFF1A8070, 0xFF1565C0, 0xFF6A1B9A, 0xFFAD1457, 0xFF6D4C41, 0xFFFFFFFF,
];
const markerColors = [0xFFFFE066, 0xFF77DD99, 0xFF7FD3F7, 0xFFFF9EC4, 0xFFFFB74D, 0xFFC5A3FF];

/// Hintergründe für Text-Notizen ("Ohne" = durchsichtig).
const textBackgrounds = [
  TextNote.noBackground,
  0xD9FFFFFF, // Weiss
  0x99FFE066, // Gelb
  0x9977DD99, // Grün
  0x997FD3F7, // Blau
  0x99FF9EC4, // Rosa
];

int _withAlpha(int rgb, double a) => ((a * 255).round() << 24) | (rgb & 0xFFFFFF);
double _alpha(int argb) => (argb >> 24) / 255.0;

String toolName(ToolMode m) => switch (m) {
  ToolMode.pen => 'Stift',
  ToolMode.highlighter => 'Textmarker',
  ToolMode.eraser => 'Radierer',
  ToolMode.text => 'Text',
  _ => '',
};

/// Einstellungsfenster des aktiven Werkzeugs. Lässt sich an der Kopfzeile
/// frei verschieben ([onDrag]).
class ToolPopover extends StatelessWidget {
  const ToolPopover({super.key, required this.tools, required this.onDrag});

  final ToolController tools;
  final ValueChanged<Offset> onDrag;

  static const width = 272.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mode = tools.mode;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      color: scheme.surface,
      child: Ink(
        width: width,
        decoration: BoxDecoration(gradient: VoltiColors.barGradient(Theme.of(context).brightness)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kopfzeile = Griff zum Verschieben
            MouseRegion(
              cursor: SystemMouseCursors.move,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => onDrag(d.delta),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 4, 2),
                  child: Row(
                    children: [
                      Icon(Icons.drag_indicator, size: 18, color: scheme.outline),
                      const SizedBox(width: 6),
                      Expanded(child: Text(toolName(mode), style: Theme.of(context).textTheme.titleSmall)),
                      IconButton(
                        tooltip: 'Werkzeug abwählen',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => tools.setMode(ToolMode.none),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: switch (mode) {
                  ToolMode.pen => _StrokeSettings(tools: tools, tool: InkTool.pen),
                  ToolMode.highlighter => _StrokeSettings(tools: tools, tool: InkTool.highlighter),
                  ToolMode.eraser => _EraserSettings(tools: tools),
                  ToolMode.text => _TextSettings(tools: tools),
                  _ => const SizedBox.shrink(),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 6),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

// ------------------------------------------------------------ Stift & Marker
class _StrokeSettings extends StatelessWidget {
  const _StrokeSettings({required this.tools, required this.tool});
  final ToolController tools;
  final InkTool tool;

  @override
  Widget build(BuildContext context) {
    final hl = tool == InkTool.highlighter;
    final current = hl ? tools.highlighter : tools.pen;
    void set(DrawingPreset p) => hl ? tools.setHighlighter(p) : tools.setPen(p);
    final favorites = tools.favoritesFor(tool);
    final isFavorite = favorites.any((f) => f.sameLook(current));
    final minW = DrawingPreset.minWidth(tool), maxW = DrawingPreset.maxWidth(tool);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Label('Favoriten'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final f in favorites)
              _FavoriteChip(
                selected: f.sameLook(current),
                tooltip: 'Antippen = verwenden · lange drücken = entfernen',
                onTap: () => tools.applyFavorite(f),
                onLongPress: () => _confirmRemove(context, () => tools.removeFavorite(f)),
                child: _StrokeSwatch(preset: f),
              ),
            _FavoriteChip(
              selected: false,
              tooltip: isFavorite ? 'Schon als Favorit gespeichert' : 'Aktuelle Einstellung als Favorit speichern',
              onTap: isFavorite ? null : () => tools.addCurrentAsFavorite(tool),
              child: Icon(isFavorite ? Icons.star : Icons.star_outline, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: CustomPaint(painter: _PreviewPainter(current)),
        ),
        const _Label('Farbe'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in hl ? markerColors : penColors)
              _Swatch(
                color: Color(c),
                selected: (current.color & 0xFFFFFF) == (c & 0xFFFFFF),
                onTap: () => set(current.copyWith(color: _withAlpha(c, _alpha(current.color)))),
              ),
          ],
        ),
        const _Label('Breite'),
        Slider(
          min: minW,
          max: maxW,
          value: current.width.clamp(minW, maxW),
          onChanged: (v) => set(current.copyWith(width: v)),
        ),
        const _Label('Deckkraft'),
        Slider(
          min: 0.2,
          max: 1,
          value: _alpha(current.color).clamp(0.2, 1),
          onChanged: (v) => set(current.copyWith(color: _withAlpha(current.color, v))),
        ),
      ],
    );
  }
}

Future<void> _confirmRemove(BuildContext context, VoidCallback remove) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Favorit entfernen?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Entfernen')),
      ],
    ),
  );
  if (ok == true) remove();
}

class _StrokeSwatch extends StatelessWidget {
  const _StrokeSwatch({required this.preset});
  final DrawingPreset preset;

  @override
  Widget build(BuildContext context) {
    final t =
        ((preset.width - DrawingPreset.minWidth(preset.tool)) /
                (DrawingPreset.maxWidth(preset.tool) - DrawingPreset.minWidth(preset.tool)))
            .clamp(0.0, 1.0);
    final white = (preset.color & 0xFFFFFF) == 0xFFFFFF;
    return preset.tool == InkTool.highlighter
        ? Container(
            width: 24,
            height: 6 + 10 * t,
            decoration: BoxDecoration(color: Color(preset.color), borderRadius: BorderRadius.circular(3)),
          )
        : Container(
            width: 8 + 14 * t,
            height: 8 + 14 * t,
            decoration: BoxDecoration(
              color: Color(preset.color),
              shape: BoxShape.circle,
              border: white ? Border.all(color: Theme.of(context).colorScheme.outline) : null,
            ),
          );
  }
}

// ------------------------------------------------------------------ Radierer
class _EraserSettings extends StatelessWidget {
  const _EraserSettings({required this.tools});
  final ToolController tools;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Label('Grösse'),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final (i, r) in ToolController.eraserSizes.indexed)
              Tooltip(
                message: const ['Klein', 'Mittel', 'Gross'][i],
                child: InkResponse(
                  onTap: () => tools.setEraserRadius(r),
                  radius: 28,
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: Center(
                      child: Container(
                        width: r * 1.6,
                        height: r * 1.6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tools.eraserRadius == r ? scheme.primaryContainer : null,
                          border: Border.all(
                            color: tools.eraserRadius == r ? scheme.primary : scheme.outline,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Löscht ganze Striche und Text-Notizen, die du berührst.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------- Text
class _TextSettings extends StatelessWidget {
  const _TextSettings({required this.tools});
  final ToolController tools;

  @override
  Widget build(BuildContext context) {
    final s = tools.textStyle;
    final isFavorite = tools.textFavorites.any((f) => f.sameLook(s));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Label('Favoriten'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final f in tools.textFavorites)
              _FavoriteChip(
                selected: f.sameLook(s),
                tooltip: 'Antippen = verwenden · lange drücken = entfernen',
                onTap: () => tools.setTextStyle(f.copyWith(id: s.id)),
                onLongPress: () => _confirmRemove(context, () => tools.removeTextFavorite(f)),
                child: _TextSample(style: f, fontSize: 15, text: 'Aa'),
              ),
            _FavoriteChip(
              selected: false,
              tooltip: isFavorite ? 'Schon als Favorit gespeichert' : 'Aktuellen Stil als Favorit speichern',
              onTap: isFavorite ? null : tools.addCurrentTextFavorite,
              child: Icon(isFavorite ? Icons.star : Icons.star_outline, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: _TextSample(style: s, fontSize: (s.size * 900).clamp(11, 36), text: 'Bogen ab'),
        ),
        const _Label('Grösse'),
        Slider(
          min: TextStyleSetting.minSize,
          max: TextStyleSetting.maxSize,
          value: s.size.clamp(TextStyleSetting.minSize, TextStyleSetting.maxSize),
          onChanged: (v) => tools.setTextStyle(s.copyWith(size: v)),
        ),
        const _Label('Textfarbe'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in penColors.where((c) => c != 0xFFFFFFFF))
              _Swatch(
                color: Color(c),
                selected: s.color == c,
                onTap: () => tools.setTextStyle(s.copyWith(color: c)),
              ),
          ],
        ),
        const _Label('Hintergrund'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final b in textBackgrounds)
              _Swatch(
                color: b == TextNote.noBackground ? null : Color(b),
                tooltip: b == TextNote.noBackground ? 'Ohne Hintergrund' : null,
                selected: s.background == b,
                onTap: () => tools.setTextStyle(s.copyWith(background: b)),
              ),
          ],
        ),
      ],
    );
  }
}

class _TextSample extends StatelessWidget {
  const _TextSample({required this.style, required this.fontSize, required this.text});
  final TextStyleSetting style;
  final double fontSize;
  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: style.background == TextNote.noBackground ? null : Color(style.background),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Text(
        text,
        style: TextStyle(fontSize: fontSize, color: Color(style.color), fontWeight: FontWeight.w500),
      ),
    ),
  );
}

// ------------------------------------------------------------------ Bausteine
class _FavoriteChip extends StatelessWidget {
  const _FavoriteChip({
    required this.selected,
    required this.tooltip,
    required this.onTap,
    required this.child,
    this.onLongPress,
  });

  final bool selected;
  final String tooltip;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTap: onLongPress,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap, this.tooltip});

  /// null = "ohne" (durchgestrichen dargestellt).
  final Color? color;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dot = InkResponse(
      onTap: onTap,
      radius: 18,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 3 : 1,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
        ),
        child: color == null ? CustomPaint(painter: _SlashPainter(scheme.error)) : null,
      ),
    );
    return tooltip == null ? dot : Tooltip(message: tooltip!, child: dot);
  }
}

class _SlashPainter extends CustomPainter {
  _SlashPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawLine(
    Offset(size.width * 0.2, size.height * 0.8),
    Offset(size.width * 0.8, size.height * 0.2),
    Paint()
      ..color = color
      ..strokeWidth = 2,
  );
  @override
  bool shouldRepaint(_SlashPainter old) => false;
}

/// Probestrich: eine Welle über Notenlinien, mit an- und abschwellendem Druck.
class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.preset);
  final DrawingPreset preset;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFFB0B0B0)
      ..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      final y = size.height * 0.28 + i * size.height * 0.11;
      canvas.drawLine(Offset(8, y), Offset(size.width - 8, y), line);
    }
    final pts = <InkPoint>[
      for (var i = 0; i <= 40; i++)
        InkPoint(
          0.08 + 0.84 * i / 40,
          0.5 + 0.22 * math.sin(i / 40 * 2 * math.pi),
          0.3 + 0.6 * math.sin(i / 40 * math.pi),
        ),
    ];
    // Breite ist relativ zur Seitenbreite; die Vorschau zeigt sie wie auf einer ~700 px breiten Seite.
    paintStroke(canvas, size, preset.tool, Color(preset.color), preset.width * 700 / size.width, pts);
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => !old.preset.sameLook(preset);
}
