import 'dart:math' as math;
import 'dart:ui' show PointMode, PointerDeviceKind;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
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
import 'text_layer.dart';
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
  ToolMode.stamp => 'Stempel',
  ToolMode.shape => 'Formen',
  ToolMode.lasso => 'Auswählen',
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
                      Expanded(
                        child: Text(
                          tools.layersOpen ? 'Ebenen' : toolName(mode),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: tools.layersOpen ? 'Ebenen schliessen' : 'Werkzeug abwählen',
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
    final partial = tools.eraserPartial;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('Ganze Elemente')),
            ButtonSegment(value: true, label: Text('Teilweise')),
          ],
          selected: {partial},
          onSelectionChanged: (v) => tools.setEraserPartial(v.first),
        ),
        if (partial) ...[
          const _Label('Grösse'),
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
              ? 'Löscht nur die Stellen, über die du fährst – wie ein Radiergummi. Text-Notizen werden ganz gelöscht.'
              : 'Löscht ganze Striche und Text-Notizen, die du berührst.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(
          'Das Radierer-Ende des Stifts radiert genauso.',
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
      tooltip: stampGlyph(glyph)?.label ?? '',
      onTap: () => tools.setStamp(st.copyWith(glyph: glyph)),
      child: SizedBox(width: 36, height: 36, child: CustomPaint(painter: _GlyphPainter(glyph, Color(st.color)))),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (recent.isNotEmpty) ...[
          const _Label('Zuletzt benutzt'),
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
            for (final c in stampCatalog) Tab(height: 34, text: c.name),
            const Tab(height: 34, text: 'Eigene'),
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
          'Auf die Seite tippen, um den Stempel zu setzen. Einen gesetzten Stempel ziehen, um ihn zu verschieben.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const _Label('Grösse'),
        Slider(
          min: StampSetting.minSize,
          max: StampSetting.maxSize,
          value: st.size.clamp(StampSetting.minSize, StampSetting.maxSize),
          onChanged: (v) => tools.setStamp(st.copyWith(size: v)),
        ),
        // Eigene Stempel behalten ihre Farben.
        if (st.custom == null) ...[
          const _Label('Farbe'),
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
                  tooltip: '${s.name} · lange drücken = ändern',
                  onTap: () => tools.setStamp(st.copyWith(custom: s.id)),
                  onLongPress: () => _menu(context, s),
                  child: SizedBox(width: 36, height: 36, child: CustomPaint(painter: _CustomStampIcon(s.id))),
                ),
              _FavoriteChip(
                selected: false,
                tooltip: 'Eigenes Bild als Stempel importieren',
                onTap: () => importCustomStamp(context, tools),
                child: const Icon(Icons.add_photo_alternate_outlined, size: 22),
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
            child: const Text('Mittelpunkt und Name ändern …'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('remove'),
            child: const Text('Aus der Auswahl entfernen'),
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
            if (count == 0)
              Text(
                'Mit dem Stift oder der Maus einkreisen, was du auswählen möchtest. Strg+A wählt alles auf der Seite.',
                style: hint,
              )
            else ...[
              Text(
                count == 1 ? '1 Element ausgewählt' : '$count Elemente ausgewählt',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  action(Icons.copy, 'Kopieren', 'Strg+C', tools.copySelection),
                  action(Icons.content_cut, 'Ausschneiden', 'Strg+X', tools.cutSelection),
                  action(Icons.library_add_outlined, 'Duplizieren', 'Strg+D', tools.duplicateSelection),
                  action(Icons.delete_outline, 'Löschen', 'Entf', tools.deleteSelection),
                ],
              ),
              if (ink != null && ink!.drawableLayers.length > 1) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: PopupMenuButton<String>(
                    tooltip: 'Auf eine andere Ebene legen',
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
                        label: const Text('Auf Ebene …'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const _Label('Farbe ändern'),
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
                'Ziehen verschiebt die Auswahl. Am runden Griff unten rechts ziehen macht sie grösser oder kleiner.',
                style: hint,
              ),
            ],
            if (clip != null && ink != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => tools.pasteInto(ink!, page),
                icon: const Icon(Icons.content_paste, size: 18),
                label: Text('Einfügen auf Seite $page'),
              ),
              const SizedBox(height: 4),
              Text('Auch in ein anderes Stück: dort eine Seite antippen, dann einfügen (Strg+V).', style: hint),
            ],
          ],
        );
      },
    );
  }
}

// -------------------------------------------------------------------- Formen
const _shapeNames = {
  ShapeKind.line: 'Linie',
  ShapeKind.arrow: 'Pfeil',
  ShapeKind.rectangle: 'Rechteck',
  ShapeKind.ellipse: 'Ellipse',
  ShapeKind.crescendo: 'Crescendo',
  ShapeKind.decrescendo: 'Decrescendo',
  ShapeKind.slur: 'Bogen',
  ShapeKind.staff: 'Notenlinien',
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
        const _Label('Form'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final k in ShapeKind.values)
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
          tools.shapeKind == ShapeKind.staff
              ? 'Vom Anfang zum Ende ziehen. Nach unten ziehen bestimmt die Höhe, nur waagrecht ergibt die übliche Höhe.'
              : 'Auf der Seite vom Anfang zum Ende ziehen.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const _Label('Farbe'),
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
        const _Label('Breite'),
        Slider(
          min: DrawingPreset.minPenWidth,
          max: DrawingPreset.maxPenWidth,
          value: style.width.clamp(DrawingPreset.minPenWidth, DrawingPreset.maxPenWidth),
          onChanged: (v) => tools.setShape(style.copyWith(width: v)),
        ),
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
      _ => (Offset(2, size.height / 2 + 4), Offset(size.width - 2, size.height / 2 + 4)),
    };
    for (final piece in shapeGeometry(kind, a, b, 1.5, pageWidth: size.width * 28)) {
      canvas.drawPoints(PointMode.polygon, piece, paint);
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
        const _Label('Schrift'),
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
              selected: s.bold,
              tooltip: 'Bold',
              onTap: () => tools.setTextStyle(s.copyWith(bold: !s.bold)),
              child: const Text(
                'B',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.black87),
              ),
            ),
            const SizedBox(width: 6),
            _ToggleBox(
              selected: s.italic,
              tooltip: 'Italic',
              onTap: () => tools.setTextStyle(s.copyWith(italic: !s.italic)),
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
          ],
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
  final VoidCallback onTap;
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
