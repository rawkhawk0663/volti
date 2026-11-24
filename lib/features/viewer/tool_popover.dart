import 'dart:math' as math;
import 'dart:ui' show PointMode, PointerDeviceKind;

import 'package:flutter/material.dart';

import '../../core/ink/stamp_catalog.dart';
import '../../core/ink/stroke.dart';
import '../../core/ink/text_note.dart';
import '../../core/ink/tool_settings.dart';
import '../../core/ink/custom_stamps.dart';
import 'custom_stamp_editor.dart';
import 'custom_stamp_registry.dart';
import 'ink_controller.dart';
import 'ink_layer.dart';
import 'layers_panel.dart';
import 'shapes.dart';
import 'stamp_paint.dart';
import 'rich_text.dart';
import 'text_layer.dart';
import 'tool_controller.dart';
import 'tab_keys.dart';
import 'tab_paint.dart';
import '../../app/touch_keyboard.dart';
import 'tab_session.dart';
import '../../core/ink/tab_block.dart';
import '../../app/l10n.dart';
import '../../core/ink/stamp_names.dart';

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
  ToolMode.pen => tr('Stift', 'Pen'),
  ToolMode.highlighter => tr('Textmarker', 'Highlighter'),
  ToolMode.eraser => tr('Radierer', 'Eraser'),
  ToolMode.text => tr('Text', 'Text'),
  ToolMode.stamp => tr('Stempel', 'Stamps'),
  ToolMode.shape => tr('Formen', 'Shapes'),
  ToolMode.lasso => tr('Auswählen', 'Select'),
  ToolMode.link => tr('Sprungmarke', 'Jump link'),
  ToolMode.move => tr('Verschieben', 'Move'),
  ToolMode.tab => tr('Tabulatur', 'Tablature'),
  _ => '',
};

/// Einstellungsfenster des aktiven Werkzeugs. Lässt sich an der Kopfzeile
/// frei verschieben ([onDrag]).
class ToolPopover extends StatelessWidget {
  const ToolPopover({super.key, required this.tools, required this.onDrag, this.ink, this.page = 1});

  final ToolController tools;

  /// Zuletzt berührte Seite – dorthin wird eingefügt.
  final InkController? ink;
  final int page;
  final ValueChanged<Offset> onDrag;

  static const width = 272.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mode = tools.mode;
    return Material(
      // Kein Schatten: Er müsste bei jedem Bild beim Zeichnen mitgemalt werden.
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      color: scheme.surface,
      child: Ink(
        width: width,
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
                      Expanded(
                        child: Text(
                          tools.layersOpen ? tr('Ebenen', 'Layers') : toolName(mode),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: tools.layersOpen
                            ? tr('Ebenen schliessen', 'Close layers')
                            : tr('Werkzeug abwählen', 'Deselect tool'),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => tools.layersOpen ? tools.toggleLayers() : tools.setMode(ToolMode.none),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Wohin gezeichnet wird – nur sichtbar, wenn es mehrere Ebenen gibt.
            if (ink != null && mode != ToolMode.eraser && !tools.layersOpen) ActiveLayerChip(ink: ink!, tools: tools),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: tools.layersOpen && ink != null
                    ? LayersPanel(ink: ink!)
                    : switch (mode) {
                        ToolMode.pen => _StrokeSettings(tools: tools, tool: InkTool.pen),
                        ToolMode.highlighter => _StrokeSettings(tools: tools, tool: InkTool.highlighter),
                        ToolMode.eraser => _EraserSettings(tools: tools),
                        ToolMode.text => _TextSettings(tools: tools),
                        ToolMode.stamp => _StampSettings(tools: tools),
                        ToolMode.shape => _ShapeSettings(tools: tools),
                        ToolMode.lasso => _LassoSettings(tools: tools, ink: ink, page: page),
                        ToolMode.link => _LinkSettings(tools: tools),
                        ToolMode.move => const _MoveSettings(),
                        ToolMode.tab => _TabSettings(tools: tools),
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
        _Label(tr('Favoriten', 'Favourites')),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final f in favorites)
              _FavoriteChip(
                selected: f.sameLook(current),
                tooltip: tr('Antippen = verwenden · lange drücken = entfernen', 'Tap = use · long press = remove'),
                onTap: () => tools.applyFavorite(f),
                onLongPress: () => _confirmRemove(context, () => tools.removeFavorite(f)),
                child: _StrokeSwatch(preset: f),
              ),
            _FavoriteChip(
              selected: false,
              tooltip: isFavorite
                  ? tr('Schon als Favorit gespeichert', 'Already saved as a favourite')
                  : tr('Aktuelle Einstellung als Favorit speichern', 'Save current setting as a favourite'),
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
        _Label(tr('Farbe', 'Colour')),
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
        _Label(tr('Breite', 'Width')),
        Slider(
          min: minW,
          max: maxW,
          value: current.width.clamp(minW, maxW),
          onChanged: (v) => set(current.copyWith(width: v)),
        ),
        _Label(tr('Deckkraft', 'Opacity')),
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
      title: Text(tr('Favorit entfernen?', 'Remove favourite?')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Abbrechen', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Entfernen', 'Remove'))),
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
    final partial = tools.eraserPartial;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: false, label: Text(tr('Ganze Elemente', 'Whole elements'))),
            ButtonSegment(value: true, label: Text(tr('Teilweise', 'Partial'))),
          ],
          selected: {partial},
          onSelectionChanged: (v) => tools.setEraserPartial(v.first),
        ),
        if (partial) ...[
          _Label(tr('Grösse', 'Size')),
          Row(
            children: [
              Expanded(
                child: Slider(
                  min: ToolController.eraserMin,
                  max: ToolController.eraserMax,
                  value: tools.eraserRadius.clamp(ToolController.eraserMin, ToolController.eraserMax),
                  onChanged: tools.setEraserRadius,
                ),
              ),
              // Vorschau in echter Grösse
              SizedBox(
                width: ToolController.eraserMax * 2 + 4,
                height: ToolController.eraserMax * 2 + 4,
                child: Center(
                  child: Container(
                    width: tools.eraserRadius * 2,
                    height: tools.eraserRadius * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primaryContainer,
                      border: Border.all(color: scheme.primary, width: 1.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Text(
          partial
              ? tr(
                  'Löscht nur die Stellen, über die du fährst – wie ein Radiergummi. Text-Notizen werden ganz gelöscht.',
                  'Erases only where you move – like a rubber. Text notes are erased completely.',
                )
              : tr(
                  'Löscht ganze Striche und Text-Notizen, die du berührst.',
                  'Erases whole strokes and text notes that you touch.',
                ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(
          tr('Das Radierer-Ende des Stifts radiert genauso.', 'The eraser end of the pen erases the same way.'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- Stempel
class _StampSettings extends StatefulWidget {
  const _StampSettings({required this.tools});
  final ToolController tools;

  @override
  State<_StampSettings> createState() => _StampSettingsState();
}

class _StampSettingsState extends State<_StampSettings> with SingleTickerProviderStateMixin {
  // Letzter Tab: "Eigene" (selbst importierte Bilder).
  late final TabController _tabs = TabController(
    length: stampCatalog.length + 1,
    vsync: this,
    initialIndex: widget.tools.stamp.custom != null ? stampCatalog.length : _categoryOf(widget.tools.stamp.glyph),
  );

  /// Höhe der Symbol-Fläche: vier Reihen, mehr wird darin gescrollt.
  static const _gridHeight = 4 * 40.0 + 3 * 6 + 12;

  static int _categoryOf(int glyph) {
    final i = stampCatalog.indexWhere((c) => c.glyphs.any((g) => g.codepoint == glyph));
    return i < 0 ? 0 : i;
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tools = widget.tools;
    final st = tools.stamp;
    final recent = tools.recentStamps;
    final scheme = Theme.of(context).colorScheme;
    Widget cell(int glyph) => _FavoriteChip(
      selected: st.custom == null && st.glyph == glyph,
      tooltip: stampName(stampGlyph(glyph)?.label ?? ''),
      onTap: () => tools.setStamp(st.copyWith(glyph: glyph)),
      child: SizedBox(width: 36, height: 36, child: CustomPaint(painter: _GlyphPainter(glyph, Color(st.color)))),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (recent.isNotEmpty) ...[
          _Label(tr('Zuletzt benutzt', 'Recently used')),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final g in recent.take(5)) cell(g)]),
          const SizedBox(height: 6),
        ],
        // Gruppen als Tabs; nach links/rechts wischen wechselt die Gruppe.
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          padding: EdgeInsets.zero,
          labelPadding: const EdgeInsets.symmetric(horizontal: 10),
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          dividerColor: scheme.outlineVariant,
          tabs: [
            for (final c in stampCatalog) Tab(height: 34, text: stampName(c.name)),
            Tab(height: 34, text: tr('Eigene', 'Own')),
          ],
        ),
        SizedBox(
          height: _gridHeight,
          child: ScrollConfiguration(
            // Auch mit Maus und Stift wischen (nicht nur mit dem Finger).
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.stylus,
                PointerDeviceKind.invertedStylus,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: TabBarView(
              controller: _tabs,
              children: [
                for (final c in stampCatalog)
                  SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Wrap(spacing: 6, runSpacing: 6, children: [for (final g in c.glyphs) cell(g.codepoint)]),
                  ),
                _CustomStampsTab(tools: tools),
              ],
            ),
          ),
        ),
        _PageDots(controller: _tabs),
        const SizedBox(height: 4),
        Text(
          tr(
            'Auf die Seite tippen, um den Stempel zu setzen. Einen gesetzten Stempel ziehen, um ihn zu verschieben.',
            'Tap the page to place the stamp. Drag a placed stamp to move it.',
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        _Label(tr('Grösse', 'Size')),
        Slider(
          min: StampSetting.minSize,
          max: StampSetting.maxSize,
          value: st.size.clamp(StampSetting.minSize, StampSetting.maxSize),
          onChanged: (v) => tools.setStamp(st.copyWith(size: v)),
        ),
        // Eigene Stempel behalten ihre Farben.
        if (st.custom == null) ...[
          _Label(tr('Farbe', 'Colour')),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in penColors.where((c) => c != 0xFFFFFFFF))
                _Swatch(
                  color: Color(c),
                  selected: st.color == c,
                  onTap: () => tools.setStamp(st.copyWith(color: c)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Tab "Eigene": selbst importierte Bilder als Stempel.
class _CustomStampsTab extends StatelessWidget {
  const _CustomStampsTab({required this.tools});
  final ToolController tools;

  @override
  Widget build(BuildContext context) {
    final registry = CustomStamps.instance;
    if (registry == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: registry,
      builder: (context, _) {
        final st = tools.stamp;
        return SingleChildScrollView(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in registry.stamps)
                _FavoriteChip(
                  selected: st.custom == s.id,
                  tooltip: tr('${s.name} · lange drücken = ändern', '${s.name} · long press = edit'),
                  onTap: () => tools.setStamp(st.copyWith(custom: s.id)),
                  onLongPress: () => _menu(context, s),
                  child: SizedBox(width: 36, height: 36, child: CustomPaint(painter: _CustomStampIcon(s.id))),
                ),
              _FavoriteChip(
                selected: false,
                plain: true,
                tooltip: tr('Eigenes Bild als Stempel importieren', 'Import your own image as a stamp'),
                onTap: () => importCustomStamp(context, tools),
                child: Icon(Icons.add_photo_alternate_outlined, size: 22, color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _menu(BuildContext context, CustomStamp s) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(s.name),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('edit'),
            child: Text(tr('Mittelpunkt und Name ändern …', 'Change centre point and name …')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('remove'),
            child: Text(tr('Aus der Auswahl entfernen', 'Remove from the selection')),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (action == 'edit') await editCustomStamp(context, s);
    if (action == 'remove') {
      await CustomStamps.instance?.remove(s.id);
      if (tools.stamp.custom == s.id) tools.setStamp(tools.stamp.copyWith(glyph: tools.stamp.glyph));
    }
  }
}

class _CustomStampIcon extends CustomPainter {
  _CustomStampIcon(this.id);
  final String id;

  @override
  void paint(Canvas canvas, Size size) {
    final s = CustomStamps.instance?.byId(id);
    final aspect = s?.aspect ?? 1;
    // So gross wie möglich in die Fläche einpassen.
    final h = math.min(size.height * 0.9, size.width * 0.9 / aspect);
    final rect = Rect.fromCenter(center: size.center(Offset.zero), width: h * aspect, height: h);
    final at = Offset(rect.left + (s?.anchorX ?? 0.5) * rect.width, rect.top + (s?.anchorY ?? 0.5) * rect.height);
    paintCustomStamp(canvas, id, at, h);
  }

  @override
  bool shouldRepaint(_CustomStampIcon old) => true;
}

/// Ein Stempel-Symbol, eingepasst in seine Fläche.
class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);
  final int glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final g = stampGlyph(glyph);
    final fs = g == null ? 24.0 : math.min(30.0, math.min(size.width * 0.9 / g.width, size.height * 0.9 / g.height));
    paintGlyph(canvas, glyph, size.center(Offset.zero), fs, color);
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph || old.color != color;
}

// ------------------------------------------------------------ Sprungmarken
class _LinkSettings extends StatelessWidget {
  const _LinkSettings({required this.tools});
  final ToolController tools;

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return ValueListenableBuilder(
      valueListenable: tools.linkStart,
      builder: (context, start, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 6),
          if (start == null) ...[
            Text(tr('1. Startpunkt antippen', '1. Tap the start point'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              tr(
                'Zum Beispiel beim «D.S.» oder am Ende einer Wiederholung. Dort erscheint ein blauer Punkt.',
                'For example at the «D.S.» or at the end of a repeat. A blue dot appears there.',
              ),
              style: hint,
            ),
          ] else ...[
            Text(tr('2. Ziel antippen', '2. Tap the target'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              tr(
                'Zum Beispiel beim Segno. Du kannst vorher umblättern.',
                'For example at the segno. You can turn pages first.',
              ),
              style: hint,
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => tools.linkStart.value = null, child: Text(tr('Abbrechen', 'Cancel'))),
          ],
          const SizedBox(height: 12),
          Text(
            tr(
              'Beim Spielen springt Volti beim Antippen des blauen Punkts zum Ziel, das kurz orange aufblinkt. '
                  'Hier: Punkt ziehen verschiebt ihn, antippen zeigt Ziel ändern und Löschen.',
              'While playing, tapping the blue dot jumps to the target, which briefly flashes orange. '
                  'Here: drag a dot to move it, tap it to change the target or delete it.',
            ),
            style: hint,
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- Lasso
class _LassoSettings extends StatelessWidget {
  const _LassoSettings({required this.tools, required this.ink, required this.page});
  final ToolController tools;
  final InkController? ink;
  final int page;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hint = Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return ListenableBuilder(
      // Auswahl und Anmerkungen (z. B. nach Rückgängig) können sich ändern.
      listenable: Listenable.merge([tools, tools.selection, ?ink]),
      builder: (context, _) {
        final sel = tools.selection.value;
        final count = sel?.live.count ?? 0;
        final clip = tools.clipboard;
        Widget action(IconData icon, String label, String shortcut, VoidCallback? onTap) => Tooltip(
          message: shortcut,
          child: OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 18),
            label: Text(label),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 6),
            // Was das Einkreisen tut: Anmerkungen auswählen oder Takte kopieren.
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text(tr('Anmerkungen', 'Notes'))),
                ButtonSegment(value: true, label: Text(tr('Takte kopieren', 'Copy bars'))),
              ],
              selected: {tools.snippetMode},
              onSelectionChanged: (v) => tools.setSnippetMode(v.first),
            ),
            const SizedBox(height: 8),
            if (tools.snippetMode)
              Text(
                tr(
                  'Takte einkreisen: Sie werden samt Anmerkungen als Bild kopiert. Dann eine Seite antippen (auch in '
                      'einem anderen Stück) und «Einfügen». Danach lässt es sich wie ein Stempel verschieben und vergrössern.',
                  'Circle the bars: they are copied as an image, including your notes. Then tap a page (even in '
                      'another piece) and «Paste». After that you can move and resize it like a stamp.',
                ),
                style: hint,
              )
            else if (count == 0)
              Text(
                tr(
                  'Mit dem Stift oder der Maus einkreisen, was du auswählen möchtest. Strg+A wählt alles auf der Seite.',
                  'Circle what you want to select with the pen or mouse. Ctrl+A selects everything on the page.',
                ),
                style: hint,
              )
            else ...[
              Text(
                count == 1
                    ? tr('1 Element ausgewählt', '1 element selected')
                    : tr('$count Elemente ausgewählt', '$count elements selected'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  action(Icons.copy, tr('Kopieren', 'Copy'), tr('Strg+C', 'Ctrl+C'), tools.copySelection),
                  action(Icons.content_cut, tr('Ausschneiden', 'Cut'), tr('Strg+X', 'Ctrl+X'), tools.cutSelection),
                  action(
                    Icons.library_add_outlined,
                    tr('Duplizieren', 'Duplicate'),
                    tr('Strg+D', 'Ctrl+D'),
                    tools.duplicateSelection,
                  ),
                  action(Icons.delete_outline, tr('Löschen', 'Delete'), tr('Entf', 'Del'), tools.deleteSelection),
                ],
              ),
              if (ink != null && ink!.drawableLayers.length > 1) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: PopupMenuButton<String>(
                    tooltip: tr('Auf eine andere Ebene legen', 'Put on another layer'),
                    onSelected: (id) {
                      final s = tools.selection.value;
                      if (s != null) s.controller.moveToLayer(s.live, id);
                    },
                    itemBuilder: (_) => [
                      for (final l in ink!.drawableLayers.reversed)
                        PopupMenuItem(
                          value: l.id,
                          child: Text(
                            ink!.annotations.groupOf(l) == null
                                ? l.name
                                : '${ink!.annotations.groupOf(l)!.name} › ${l.name}',
                          ),
                        ),
                    ],
                    child: IgnorePointer(
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.layers_outlined, size: 18),
                        label: Text(tr('Auf Ebene …', 'To layer …')),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              _Label(tr('Farbe ändern', 'Change colour')),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in penColors.where((c) => c != 0xFFFFFFFF))
                    _Swatch(color: Color(c), selected: false, onTap: () => tools.recolorSelection(c)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                tr(
                  'Ziehen verschiebt die Auswahl. Am runden Griff unten rechts ziehen macht sie grösser oder kleiner.',
                  'Dragging moves the selection. Dragging the round handle at the bottom right makes it bigger or smaller.',
                ),
                style: hint,
              ),
            ],
            if (clip != null && ink != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => tools.pasteInto(ink!, page),
                icon: const Icon(Icons.content_paste, size: 18),
                label: Text(tr('Einfügen auf Seite $page', 'Paste on page $page')),
              ),
              const SizedBox(height: 4),
              Text(
                tr(
                  'Auch in ein anderes Stück: dort eine Seite antippen, dann einfügen (Strg+V).',
                  'Into another piece too: tap a page there, then paste (Ctrl+V).',
                ),
                style: hint,
              ),
            ],
          ],
        );
      },
    );
  }
}

// -------------------------------------------------------------------- Formen
Map<ShapeKind, String> get _shapeNames => {
  ShapeKind.line: tr('Linie', 'Line'),
  ShapeKind.arrow: tr('Pfeil', 'Arrow'),
  ShapeKind.rectangle: tr('Rechteck', 'Rectangle'),
  ShapeKind.ellipse: tr('Ellipse', 'Ellipse'),
  ShapeKind.crescendo: tr('Crescendo / Decrescendo', 'Crescendo / decrescendo'),
  ShapeKind.decrescendo: tr('Crescendo / Decrescendo', 'Crescendo / decrescendo'),
  ShapeKind.slur: tr('Bogen', 'Slur'),
  ShapeKind.staff: tr('Notenlinien', 'Staff lines'),
  ShapeKind.tab: tr('Tabulatur (6 Linien)', 'Tablature (6 lines)'),
};

class _ShapeSettings extends StatelessWidget {
  const _ShapeSettings({required this.tools});
  final ToolController tools;

  @override
  Widget build(BuildContext context) {
    final style = tools.shape;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Label(tr('Form', 'Shape')),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final k in offeredShapeKinds)
              _FavoriteChip(
                selected: tools.shapeKind == k,
                tooltip: _shapeNames[k]!,
                onTap: () => tools.setShapeKind(k),
                child: SizedBox(width: 30, height: 30, child: CustomPaint(painter: _ShapeIconPainter(k))),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          switch (tools.shapeKind) {
            ShapeKind.staff || ShapeKind.tab => tr(
              'Vom Anfang zum Ende ziehen. Nach unten ziehen bestimmt die Höhe, nur waagrecht ergibt die übliche Höhe.',
              'Drag from start to end. Dragging downwards sets the height; dragging only sideways gives the usual height.',
            ),
            ShapeKind.crescendo || ShapeKind.decrescendo => tr(
              'Von der Spitze zum offenen Ende ziehen: nach rechts = crescendo, nach links = decrescendo.',
              'Drag from the point to the open end: to the right = crescendo, to the left = decrescendo.',
            ),
            _ => tr('Auf der Seite vom Anfang zum Ende ziehen.', 'Drag on the page from start to end.'),
          },
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        _Label(tr('Farbe', 'Colour')),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in penColors)
              _Swatch(
                color: Color(c),
                selected: style.color == c,
                onTap: () => tools.setShape(style.copyWith(color: c)),
              ),
          ],
        ),
        _Label(tr('Breite', 'Width')),
        Slider(
          min: DrawingPreset.minPenWidth,
          max: DrawingPreset.maxPenWidth,
          value: style.width.clamp(DrawingPreset.minPenWidth, DrawingPreset.maxPenWidth),
          onChanged: (v) => tools.setShape(style.copyWith(width: v)),
        ),
        // Füllung nur bei geschlossenen Formen (z. B. weisses Rechteck zum Abdecken).
        if (shapeCanFill(tools.shapeKind)) ...[
          _Label(tr('Füllung', 'Fill')),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Swatch(
                color: null,
                tooltip: tr('Ohne Füllung', 'No fill'),
                selected: tools.shapeFill == 0,
                onTap: () => tools.setShapeFill(0),
              ),
              for (final c in [0xFFFFFFFF, ...penColors.where((c) => c != 0xFFFFFFFF)])
                _Swatch(color: Color(c), selected: tools.shapeFill == c, onTap: () => tools.setShapeFill(c)),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(tr('Rand zeichnen', 'Draw outline')),
            subtitle: Text(
              tr('Aus: nur die Fläche, z. B. weiss zum Abdecken.', 'Off: only the area, e.g. white to cover up.'),
            ),
            value: tools.shapeOutline,
            onChanged: tools.shapeFill == 0 ? null : tools.setShapeOutline,
          ),
        ],
      ],
    );
  }
}

class _ShapeIconPainter extends CustomPainter {
  _ShapeIconPainter(this.kind);
  final ShapeKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xDD1B1B1B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final (a, b) = switch (kind) {
      ShapeKind.rectangle || ShapeKind.ellipse => (const Offset(3, 7), Offset(size.width - 3, size.height - 7)),
      ShapeKind.line || ShapeKind.arrow => (Offset(3, size.height - 5), Offset(size.width - 3, 5)),
      ShapeKind.staff => (const Offset(2, 7), Offset(size.width - 2, size.height - 7)),
      ShapeKind.tab => (const Offset(2, 4), Offset(size.width - 2, size.height - 4)),
      _ => (Offset(2, size.height / 2 + 4), Offset(size.width - 2, size.height / 2 + 4)),
    };
    // Die Tabulatur ist höher – mit kleinerer „Seite“ passt sie ins Symbol.
    final page = size.width * (kind == ShapeKind.tab ? 12 : 28);
    for (final piece in shapeGeometry(kind, a, b, 1.5, pageWidth: page)) {
      if (piece.solid) canvas.drawPath(Path()..addPolygon(piece.points, true), Paint()..color = paint.color);
      canvas.drawPoints(PointMode.polygon, piece.points, paint);
    }
  }

  @override
  bool shouldRepaint(_ShapeIconPainter old) => old.kind != kind;
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
        _Label(tr('Favoriten', 'Favourites')),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final f in tools.textFavorites)
              _FavoriteChip(
                selected: f.sameLook(s),
                tooltip: tr('Antippen = verwenden · lange drücken = entfernen', 'Tap = use · long press = remove'),
                onTap: () => tools.setTextStyle(f.copyWith(id: s.id)),
                onLongPress: () => _confirmRemove(context, () => tools.removeTextFavorite(f)),
                child: _TextSample(style: f, fontSize: 15, text: 'Aa'),
              ),
            _FavoriteChip(
              selected: false,
              tooltip: isFavorite
                  ? tr('Schon als Favorit gespeichert', 'Already saved as a favourite')
                  : tr('Aktuellen Stil als Favorit speichern', 'Save current style as a favourite'),
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
          child: _TextSample(style: s, fontSize: (s.size * 900).clamp(11, 36), text: tr('Bogen ab', 'Sample')),
        ),
        // Ist in der getippten Notiz etwas markiert, gelten Fett, Kursiv,
        // Unterstrichen und Farbe nur für diesen Teil.
        ValueListenableBuilder<RichTextTarget?>(
          valueListenable: tools.richText,
          builder: (context, target, _) => ListenableBuilder(
            listenable: target?.controller ?? tools.richText,
            builder: (context, _) {
              final part = target != null && target.hasSelection;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Label(part ? tr('Schrift · nur Markiertes', 'Font · selection only') : tr('Schrift', 'Font')),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _FontPicker(
                          selected: s.font,
                          onSelected: (f) => tools.setTextStyle(s.copyWith(font: f)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _ToggleBox(
                        selected: part ? target.bold : s.bold,
                        tooltip: tr('Fett (Strg+B)', 'Bold (Ctrl+B)'),
                        onTap: () => part ? target.toggleBold() : tools.setTextStyle(s.copyWith(bold: !s.bold)),
                        child: const Text(
                          'B',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.black87),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _ToggleBox(
                        selected: part ? target.italic : s.italic,
                        tooltip: tr('Kursiv (Strg+I)', 'Italic (Ctrl+I)'),
                        onTap: () => part ? target.toggleItalic() : tools.setTextStyle(s.copyWith(italic: !s.italic)),
                        child: const Text(
                          'I',
                          style: TextStyle(
                            fontSize: 17,
                            fontStyle: FontStyle.italic,
                            fontFamily: 'VoltiSerif',
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _ToggleBox(
                        selected: part && target.underline,
                        tooltip: tr(
                          'Unterstrichen (Strg+U) – für markierten Text',
                          'Underline (Ctrl+U) – for selected text',
                        ),
                        onTap: target == null
                            ? null
                            : () {
                                if (part) {
                                  target.toggleUnderline();
                                } else {
                                  // Nichts markiert: die ganze Notiz.
                                  final c = target.controller;
                                  final sel = c.selection;
                                  c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
                                  target.toggleUnderline();
                                  c.selection = sel;
                                }
                              },
                        child: const Text(
                          'U',
                          style: TextStyle(fontSize: 17, decoration: TextDecoration.underline, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                  _Label(tr('Grösse', 'Size')),
                  Slider(
                    min: TextStyleSetting.minSize,
                    max: TextStyleSetting.maxSize,
                    value: s.size.clamp(TextStyleSetting.minSize, TextStyleSetting.maxSize),
                    onChanged: (v) => tools.setTextStyle(s.copyWith(size: v)),
                  ),
                  _Label(
                    part
                        ? tr('Textfarbe · nur Markiertes', 'Text colour · selection only')
                        : tr('Textfarbe', 'Text colour'),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in penColors.where((c) => c != 0xFFFFFFFF))
                        _Swatch(
                          color: Color(c),
                          selected: part
                              ? target.controller.allSelected((x) => (x.color ?? s.color) == c)
                              : s.color == c,
                          onTap: () => part ? target.setColor(c) : tools.setTextStyle(s.copyWith(color: c)),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
        _Label(tr('Hintergrund', 'Background')),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final b in textBackgrounds)
              _Swatch(
                color: b == TextNote.noBackground ? null : Color(b),
                tooltip: b == TextNote.noBackground ? tr('Ohne Hintergrund', 'No background') : null,
                // Gleiche Farbe auch mit anderer Deckkraft.
                selected: b == TextNote.noBackground
                    ? s.background == b
                    : s.background != TextNote.noBackground && (s.background & 0xFFFFFF) == (b & 0xFFFFFF),
                // Farbe wählen setzt ihre übliche Deckkraft (wie bisher).
                onTap: () => tools.setTextStyle(s.copyWith(background: b)),
              ),
          ],
        ),
        if (s.background != TextNote.noBackground) ...[
          _Label(
            tr(
              'Deckkraft Hintergrund ${(_alpha(s.background) * 100).round()} %',
              'Background opacity ${(_alpha(s.background) * 100).round()} %',
            ),
          ),
          Slider(
            min: 0.2,
            max: 1,
            divisions: 16,
            value: _alpha(s.background).clamp(0.2, 1.0),
            onChanged: (v) => tools.setTextStyle(s.copyWith(background: _withAlpha(s.background, v))),
          ),
        ],
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
        style: voltiTextStyle(
          font: style.font,
          bold: style.bold,
          italic: style.italic,
          fontSize: fontSize,
          color: Color(style.color),
        ),
      ),
    ),
  );
}

// ------------------------------------------------------------------ Bausteine
const fontNames = {TextFont.sans: 'Roboto', TextFont.serif: 'Noto Serif', TextFont.mono: 'Roboto Mono'};

/// Schriftauswahl als aufklappbare Liste. Bewusst ohne eigenes Menü-Fenster:
/// So bleibt eine gerade getippte Notiz beim Auswählen offen.
class _FontPicker extends StatefulWidget {
  const _FontPicker({required this.selected, required this.onSelected});
  final TextFont selected;
  final ValueChanged<TextFont> onSelected;

  @override
  State<_FontPicker> createState() => _FontPickerState();
}

class _FontPickerState extends State<_FontPicker> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget row(TextFont f, {bool header = false}) => InkWell(
      onTap: () {
        if (header) {
          setState(() => _open = !_open);
        } else {
          setState(() => _open = false);
          widget.onSelected(f);
        }
      },
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft,
        color: !header && f == widget.selected ? scheme.primaryContainer : null,
        child: Row(
          children: [
            Expanded(
              child: Text(
                fontNames[f]!,
                overflow: TextOverflow.ellipsis,
                style: voltiTextStyle(font: f, bold: false, italic: false, fontSize: 15, color: Colors.black87),
              ),
            ),
            if (header) Icon(_open ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: Colors.black54),
          ],
        ),
      ),
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _open ? scheme.primary : scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row(widget.selected, header: true),
          if (_open) ...[Divider(height: 1, color: scheme.outlineVariant), for (final f in TextFont.values) row(f)],
        ],
      ),
    );
  }
}

class _ToggleBox extends StatelessWidget {
  const _ToggleBox({required this.selected, required this.tooltip, required this.onTap, required this.child});
  final bool selected;
  final String tooltip;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 40,
          constraints: const BoxConstraints(minWidth: 40),
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

class _FavoriteChip extends StatelessWidget {
  const _FavoriteChip({
    required this.selected,
    required this.tooltip,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.plain = false,
  });

  /// Ohne weissen Grund (z. B. für den Knopf "Importieren").
  final bool plain;

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
            color: selected ? scheme.primaryContainer : (plain ? Colors.transparent : Colors.white),
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

/// Kleine Punkte unter den Stempel-Gruppen: zeigen, wo man gerade ist.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.controller});
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller.animation!,
      builder: (context, _) {
        final pos = controller.animation!.value;
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < controller.length; i++)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(scheme.primary, scheme.outlineVariant, (pos - i).abs().clamp(0.0, 1.0)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ----------------------------------------------------------------- Verschieben
class _MoveSettings extends StatelessWidget {
  const _MoveSettings();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        tr(
          'Einen Strich, Stempel oder eine Text-Notiz mit dem Stift (oder der Maus) anfassen und an die '
              'neue Stelle ziehen. Mehrere auf einmal: mit „Auswählen“ einkreisen.',
          'Grab a stroke, stamp or text note with the pen (or mouse) and drag it to its '
              'new place. Several at once: circle them with “Select”.',
        ),
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}

// ----------------------------------------------------------------- Tabulatur
/// Einstellungen und Zahlenfeld für Tabulaturen. Das Zahlenfeld schreibt in
/// die Tabulatur, in der gerade der Cursor steht – so geht alles auch ohne
/// Tastatur (oder ohne Ziffernblock).
class _TabSettings extends StatelessWidget {
  const _TabSettings({required this.tools});
  final ToolController tools;

  /// Notenwerte in der Notenschrift Bravura (ganze bis 32tel, Hals nach oben).
  static const _noteGlyphs = {1: 0xE1D2, 2: 0xE1D3, 4: 0xE1D5, 8: 0xE1D7, 16: 0xE1D9, 32: 0xE1DB};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return ValueListenableBuilder<TabSession?>(
      valueListenable: tools.tabSession,
      builder: (context, session, _) {
        final block = session?.block;
        final bg = block?.background ?? tools.tabBackground;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              session == null
                  ? tr(
                      'Mit Stift oder Maus auf der Seite ziehen (oder tippen), um eine Tabulatur anzulegen. '
                          'Eine vorhandene antippen, um darin zu schreiben.',
                      'Drag (or tap) on the page with the pen or mouse to add a tablature. '
                          'Tap an existing one to write in it.',
                    )
                  : tr(
                      'Bundzahl tippen (Ziffern-Reihe oben, Ziffernblock oder hier). Zweistellig: rasch hintereinander.',
                      'Type the fret number (top row, number pad or here). Two digits: type them quickly.',
                    ),
              style: muted,
            ),
            if (session != null)
              ExcludeFocus(
                child: _TabKeypad(session: session, tools: tools),
              ),
            _TabMeter(tools: tools, session: session),
            _TabSize(tools: tools, session: session, gap: block?.gap ?? tools.tabGap),
            if (block != null && block.beats.any((b) => b.at != null))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => session!.ink.updateTab(
                    block.id,
                    beats: [for (final b in block.beats) b.withoutAt],
                  ),
                  icon: const Icon(Icons.auto_fix_high, size: 18),
                  label: Text(tr('Abstände wieder automatisch', 'Spacing automatic again')),
                ),
              ),
            _Label(tr('Hintergrund', 'Background')),
            _TabBackground(tools: tools, session: session, background: bg),
            if (session != null) ...[
              const SizedBox(height: 12),
              OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                overflowAlignment: OverflowBarAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      session.ink.deleteTab(session.id);
                      tools.tabSession.value = null;
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(tr('Löschen', 'Delete')),
                  ),
                  FilledButton(onPressed: () => tools.tabSession.value = null, child: Text(tr('Fertig', 'Done'))),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Text(tr('Tasten ändern: ⚙ → Noteneingabe', 'Change keys: ⚙ → Note input'), style: muted),
          ],
        );
      },
    );
  }
}

/// Taktart: ohne offene Tabulatur für neue, beim Schreiben wahlweise nur für
/// den Takt mit dem Cursor (Standard, z. B. ein eingeschobener 2/4-Takt) oder
/// für die ganze Zeile (dann werden die Taktstriche neu gesetzt).
class _TabMeter extends StatefulWidget {
  const _TabMeter({required this.tools, required this.session});
  final ToolController tools;
  final TabSession? session;

  @override
  State<_TabMeter> createState() => _TabMeterState();
}

class _TabMeterState extends State<_TabMeter> {
  bool _wholeLine = false;

  ToolController get tools => widget.tools;

  Widget _chip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
    label: Text(label),
    selected: selected,
    showCheckmark: false,
    visualDensity: VisualDensity.compact,
    onSelected: (_) => onTap(),
  );

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    if (session == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Label(tr('Taktart', 'Time signature')),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final m in <String?>[null, ...tabMeters])
                _chip(m ?? tr('frei', 'free'), tools.tabMeter == m, () => tools.setTabMeter(m)),
            ],
          ),
        ],
      );
    }
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final b = session.block;
        if (b == null) return const SizedBox.shrink();
        final n = session.measureNumber + 1;
        final whole = _wholeLine || b.beats.isEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Label(tr('Taktart', 'Time signature')),
            if (b.beats.isNotEmpty) ...[
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  ButtonSegment(value: false, label: Text(tr('Nur Takt $n', 'Bar $n only'))),
                  ButtonSegment(value: true, label: Text(tr('Ganze Zeile', 'Whole line'))),
                ],
                selected: {whole},
                onSelectionChanged: (s) => setState(() => _wholeLine = s.first),
              ),
              const SizedBox(height: 6),
            ],
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (whole)
                  for (final m in <String?>[null, ...tabMeters])
                    _chip(m ?? tr('frei', 'free'), b.meter == m, () {
                      tools.setTabMeter(m);
                      // Neue Taktart für alles: Taktstriche neu setzen (rückgängig machbar).
                      final len = meterLength(m);
                      session.ink.updateTab(
                        b.id,
                        meter: m,
                        clearMeter: m == null,
                        beats: len == null ? null : rebar(b.beats, len),
                      );
                    })
                else
                  // Nur dieser Takt: nichts verschiebt sich, der Takt danach
                  // behält seine Taktart.
                  for (final m in tabMeters) _chip(m, session.measureMeter == m, () => session.setMeasureMeter(m)),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _TabKeypad extends StatelessWidget {
  const _TabKeypad({required this.session, required this.tools});
  final TabSession session;
  final ToolController tools;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final cur = session.current;
        String tip(TabAction a) {
          final k = tools.tabKeys[a];
          return k == null ? a.label : '${a.label} (${k.label})';
        }

        Widget key(Widget child, VoidCallback onTap, {bool selected = false, String? tooltip, double width = 40}) =>
            Tooltip(
              message: tooltip ?? '',
              child: SizedBox(
                width: width,
                height: 36,
                child: Material(
                  color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onTap,
                    child: Center(child: child),
                  ),
                ),
              ),
            );
        Widget glyph(int code) => Text(
          String.fromCharCode(code),
          style: TextStyle(fontFamily: 'Bravura', fontSize: 22, height: 1, color: scheme.onSurface),
        );
        final fret = cur == null || cur.bar ? null : cur.frets[session.string];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Label(tr('Notenwert', 'Note value')),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final v in tabValues)
                  key(
                    Padding(padding: const EdgeInsets.only(top: 6), child: glyph(_TabSettings._noteGlyphs[v]!)),
                    () => session.setValue(v),
                    selected: cur != null && !cur.bar && cur.value == v,
                    tooltip: tip(TabAction.values.firstWhere((a) => a.noteValue == v)),
                    width: 37,
                  ),
                key(
                  const Text('·', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  () => session.setDots(cur?.dots == 1 ? 0 : 1),
                  selected: cur?.dots == 1,
                  tooltip: tip(TabAction.dot),
                  width: 37,
                ),
                // Doppelt punktiert
                key(
                  const Text('··', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  () => session.setDots(cur?.dots == 2 ? 0 : 2),
                  selected: cur?.dots == 2,
                  tooltip: tr('Doppelt punktiert ein/aus', 'Double-dotted on/off'),
                  width: 37,
                ),
                key(
                  const Text('3', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic)),
                  () => session.perform(TabAction.triplet),
                  selected: cur?.triplet ?? false,
                  tooltip: tip(TabAction.triplet),
                  width: 37,
                ),
                key(glyph(0xE4E5), () => session.perform(TabAction.rest), tooltip: tip(TabAction.rest), width: 37),
              ],
            ),
            _Label(tr('Technik', 'Technique')),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                key(
                  const Text('/', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  () => session.perform(TabAction.slide),
                  selected: cur?.slides.contains(session.string) ?? false,
                  tooltip: tip(TabAction.slide),
                  width: 44,
                ),
                for (final q in tabBends)
                  key(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.north_east, size: 12),
                        Text(q == 4 ? '1' : bendLabel(q), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    () => session.bend(q),
                    selected: cur?.bends[session.string] == q,
                    tooltip: tr(
                      'Bending ${bendLabel(q)} (${tools.tabKeys[TabAction.bend]?.label ?? ''})',
                      'Bend ${bendLabel(q)} (${tools.tabKeys[TabAction.bend]?.label ?? ''})',
                    ),
                    width: 46,
                  ),
              ],
            ),
            // Slides, die zu einem einzelnen Ton gehören: davor (in den Ton
            // hinein) oder danach (heraus), steigend oder fallend.
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final (into, dir, de, en) in [
                    (true, 1, 'Slide in den Ton, von unten', 'Slide into the note, from below'),
                    (true, -1, 'Slide in den Ton, von oben', 'Slide into the note, from above'),
                    (false, 1, 'Slide aus dem Ton, nach oben', 'Slide out of the note, upwards'),
                    (false, -1, 'Slide aus dem Ton, nach unten', 'Slide out of the note, downwards'),
                  ])
                    key(
                      SlideIcon(into: into, dir: dir),
                      () => into ? session.slideIn(dir) : session.slideOut(dir),
                      selected: (into ? cur?.slideIns : cur?.slideOuts)?[session.string] == dir,
                      tooltip: '${tr(de, en)} (${tools.tabKeys[into ? TabAction.slideIn : TabAction.slideOut]?.label ?? ''})',
                      width: 46,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  key(
                    const Text('x', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    () => session.perform(TabAction.ghost),
                    selected: fret == ghostNote,
                    tooltip: tip(TabAction.ghost),
                    width: 37,
                  ),
                  key(
                    const Text('⌒', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    () => session.perform(TabAction.tie),
                    selected: cur?.ties.contains(session.string) ?? false,
                    tooltip: tip(TabAction.tie),
                    width: 37,
                  ),
                  // Haltebogen von davor (z. B. über einen Zeilenumbruch).
                  key(
                    const Text('⌒(5)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    () => session.perform(TabAction.tieIn),
                    selected: cur?.tieIns.contains(session.string) ?? false,
                    tooltip: tip(TabAction.tieIn),
                    width: 50,
                  ),
                  // Hammer-on / Pull-off (Bogen über den Zahlen).
                  key(
                    const Text('H/P', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    () => session.perform(TabAction.legato),
                    selected: cur?.legato.contains(session.string) ?? false,
                    tooltip: tip(TabAction.legato),
                    width: 44,
                  ),
                  // Vorschlagsnote (Approach-Note): kleine Zahl vor der Note.
                  key(
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '3', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                          const TextSpan(text: '5', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    () => session.perform(TabAction.grace),
                    selected: session.graceInput || (cur?.graces.containsKey(session.string) ?? false),
                    tooltip: tip(TabAction.grace),
                    width: 40,
                  ),
                  key(
                    Padding(padding: const EdgeInsets.only(top: 10), child: glyph(0xE4A2)),
                    () => session.perform(TabAction.staccato),
                    selected: cur?.staccato ?? false,
                    tooltip: tip(TabAction.staccato),
                    width: 37,
                  ),
                  key(
                    Padding(padding: const EdgeInsets.only(top: 10), child: glyph(0xE4A0)),
                    () => session.perform(TabAction.accent),
                    selected: cur?.accent ?? false,
                    tooltip: tip(TabAction.accent),
                    width: 37,
                  ),
                  key(
                    const Text('P.M.', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, fontWeight: FontWeight.w700)),
                    () => session.perform(TabAction.palmMute),
                    selected: cur?.palmMute ?? false,
                    tooltip: tip(TabAction.palmMute),
                    width: 44,
                  ),
                  // Taktstriche: normal (fügt einen ein), dann die besonderen Arten.
                  for (final (kind, action) in [
                    (BarKind.normal, TabAction.bar),
                    (BarKind.repeatStart, TabAction.repeatStart),
                    (BarKind.repeatEnd, TabAction.repeatEnd),
                    (BarKind.doubleLine, TabAction.doubleBar),
                    (BarKind.last, TabAction.finalBar),
                  ])
                    key(
                      BarKindIcon(kind, color: scheme.onSurface),
                      () => session.perform(action),
                      tooltip: tip(action),
                      width: 37,
                    ),
                ],
              ),
            ),
            // Bund-Knöpfe: braucht nur, wer keine Tastatur hat (Tablet-Modus).
            ValueListenableBuilder<bool>(
              valueListenable: TouchKeyboard.tabletMode,
              builder: (context, tablet, _) {
                final show = switch (tools.tabKeypad) {
                  TabKeypad.always => true,
                  TabKeypad.never => false,
                  TabKeypad.auto => tablet,
                };
                if (!show) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Label(tr('Bund', 'Fret')),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (var f = 0; f <= TabEditor.maxFret; f++)
                          key(Text('$f'), () => session.setFret(f), selected: fret == f, width: 44),
                      ],
                    ),
                  ],
                );
              },
            ),
            // Transponieren: Markiertes (sonst der Schlag unter dem Cursor)
            // um einen Halbton tiefer bzw. höher.
            _Label(tr('Transponieren', 'Transpose')),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                key(
                  Text(tr('−½ Ton', '−½ tone'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  () => session.perform(TabAction.transposeDown),
                  tooltip: tip(TabAction.transposeDown),
                  width: 72,
                ),
                key(
                  Text(tr('+½ Ton', '+½ tone'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  () => session.perform(TabAction.transposeUp),
                  tooltip: tip(TabAction.transposeUp),
                  width: 72,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                key(
                  const Icon(Icons.arrow_back, size: 18),
                  () => session.perform(TabAction.left),
                  tooltip: tip(TabAction.left),
                ),
                key(
                  const Icon(Icons.arrow_upward, size: 18),
                  () => session.perform(TabAction.up),
                  tooltip: tip(TabAction.up),
                ),
                key(
                  const Icon(Icons.arrow_downward, size: 18),
                  () => session.perform(TabAction.down),
                  tooltip: tip(TabAction.down),
                ),
                key(
                  const Icon(Icons.arrow_forward, size: 18),
                  () => session.perform(TabAction.right),
                  tooltip: tip(TabAction.right),
                ),
                key(
                  const Icon(Icons.backspace_outlined, size: 18),
                  () => session.perform(TabAction.clearNote),
                  tooltip: tip(TabAction.clearNote),
                ),
                key(
                  const Icon(Icons.playlist_remove, size: 18),
                  () => session.perform(TabAction.deleteBeat),
                  tooltip: tip(TabAction.deleteBeat),
                ),
                key(
                  const Icon(Icons.playlist_add, size: 18),
                  () => session.perform(TabAction.insertBeat),
                  tooltip: tip(TabAction.insertBeat),
                ),
                key(
                  const Icon(Icons.add_box_outlined, size: 18),
                  () => session.perform(TabAction.insertMeasure),
                  tooltip: tip(TabAction.insertMeasure),
                ),
                key(
                  const Icon(Icons.indeterminate_check_box_outlined, size: 18),
                  () => session.perform(TabAction.deleteMeasure),
                  tooltip: tip(TabAction.deleteMeasure),
                ),
              ],
            ),
            _Label(tr('Auswahl', 'Selection')),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                key(
                  const Icon(Icons.highlight_alt, size: 18),
                  session.toggleMark,
                  selected: session.markMode,
                  tooltip: tr(
                    'Markieren: danach mit ← → erweitern (Tastatur: Umschalt + ← →, oder mit dem Stift darüberziehen)',
                    'Select: then extend with ← → (keyboard: Shift + ← →, or drag over it with the pen)',
                  ),
                  width: 56,
                ),
                key(
                  const Icon(Icons.copy, size: 18),
                  () {
                    final clip = session.copy();
                    if (clip.isNotEmpty) tools.tabClip = clip;
                  },
                  tooltip: tr('Kopieren (Strg+C)', 'Copy (Ctrl+C)'),
                  width: 56,
                ),
                key(
                  const Icon(Icons.content_cut, size: 18),
                  () {
                    final clip = session.copy();
                    if (clip.isEmpty) return;
                    tools.tabClip = clip;
                    session.hasSelection ? session.deleteSelection() : session.perform(TabAction.deleteBeat);
                  },
                  tooltip: tr('Ausschneiden (Strg+X)', 'Cut (Ctrl+X)'),
                  width: 56,
                ),
                key(
                  const Icon(Icons.content_paste, size: 18),
                  () {
                    final clip = tools.tabClip;
                    if (clip != null) session.paste(clip);
                  },
                  tooltip: tr('Einfügen (Strg+V)', 'Paste (Ctrl+V)'),
                  width: 56,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Hintergrund einer Tabulatur: Farbe (standardmässig ganz deckend) und
/// Deckkraft. Beides steckt in der gespeicherten Farbe (ARGB).
class _TabBackground extends StatefulWidget {
  const _TabBackground({required this.tools, required this.session, required this.background});
  final ToolController tools;
  final TabSession? session;
  final int background;

  /// Farben ganz deckend (die Deckkraft stellt der Regler ein).
  static const colors = [0xFFFFFFFF, 0xFFFFE066, 0xFF77DD99, 0xFF7FD3F7, 0xFFFF9EC4];

  @override
  State<_TabBackground> createState() => _TabBackgroundState();
}

class _TabBackgroundState extends State<_TabBackground> {
  /// Deckkraft während des Ziehens am Regler (sonst aus der Farbe).
  double? _dragging;

  void _apply(int argb, {bool toBlock = true}) {
    widget.tools.setTabBackground(argb);
    final s = widget.session;
    if (toBlock && s != null) s.ink.updateTab(s.id, background: argb);
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.background;
    final none = bg == TabBlock.noBackground;
    final alpha = _dragging ?? (none ? 1.0 : _alpha(bg));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Swatch(
              color: null,
              tooltip: tr('Ohne Hintergrund', 'No background'),
              selected: none,
              onTap: () => _apply(TabBlock.noBackground),
            ),
            for (final c in _TabBackground.colors)
              _Swatch(
                color: Color(c),
                selected: !none && (bg & 0xFFFFFF) == (c & 0xFFFFFF),
                // Andere Farbe: die eingestellte Deckkraft bleibt.
                onTap: () => _apply(_withAlpha(c, none ? 1.0 : _alpha(bg))),
              ),
          ],
        ),
        if (!none) ...[
          _Label(tr('Deckkraft ${(alpha * 100).round()} %', 'Opacity ${(alpha * 100).round()} %')),
          Slider(
            min: 0.2,
            max: 1,
            divisions: 16,
            value: alpha.clamp(0.2, 1.0),
            onChanged: (v) => setState(() => _dragging = v),
            // Erst beim Loslassen speichern: ein einziger Rückgängig-Schritt.
            onChangeEnd: (v) {
              setState(() => _dragging = null);
              _apply(_withAlpha(bg, v));
            },
          ),
        ],
      ],
    );
  }
}

/// Grösse einer Tabulatur: Linienabstand, Zahlen und Rhythmus wachsen mit.
class _TabSize extends StatefulWidget {
  const _TabSize({required this.tools, required this.session, required this.gap});
  final ToolController tools;
  final TabSession? session;
  final double gap;

  static const min = 0.6, max = 2.0;

  @override
  State<_TabSize> createState() => _TabSizeState();
}

class _TabSizeState extends State<_TabSize> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final factor = _dragging ?? (widget.gap / TabBlock.defaultGap).clamp(_TabSize.min, _TabSize.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Label(tr('Grösse ${(factor * 100).round()} %', 'Size ${(factor * 100).round()} %')),
        Slider(
          min: _TabSize.min,
          max: _TabSize.max,
          divisions: 28,
          value: factor.toDouble(),
          onChanged: (v) => setState(() => _dragging = v),
          // Erst beim Loslassen speichern: ein einziger Rückgängig-Schritt.
          onChangeEnd: (v) {
            setState(() => _dragging = null);
            final gap = TabBlock.defaultGap * v;
            widget.tools.setTabGap(gap);
            final s = widget.session;
            if (s != null) s.ink.updateTab(s.id, gap: gap);
          },
        ),
      ],
    );
  }
}
