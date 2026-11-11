import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ink/text_note.dart';
import '../../app/theme.dart';
import '../../core/ink/text_marks.dart';
import 'ink_controller.dart';
import 'rich_text.dart';
import 'tool_controller.dart';

/// Schriftfamilie zu einer Schriftart (Schriften liegen in der App).
String fontFamilyOf(TextFont f) => switch (f) {
  TextFont.sans => 'VoltiSans',
  TextFont.serif => 'VoltiSerif',
  TextFont.mono => 'VoltiMono',
};

/// Gemeinsamer Schriftstil für Notizen, Editor und Vorschau.
TextStyle voltiTextStyle({
  required TextFont font,
  required bool bold,
  required bool italic,
  required double fontSize,
  required Color color,
}) => TextStyle(
  fontFamily: fontFamilyOf(font),
  fontSize: fontSize,
  color: color,
  height: 1.2,
  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
  fontStyle: italic ? FontStyle.italic : FontStyle.normal,
  // Die Schriften sind "variabel": die Dicke wird hier eingestellt.
  fontVariations: [FontVariation.weight(bold ? 700 : 400)],
);

/// Schriftstil einer Text-Notiz auf einer Seite der Breite [pageWidth].
TextStyle noteStyle(TextNote t, double pageWidth) =>
    voltiTextStyle(font: t.font, bold: t.bold, italic: t.italic, fontSize: t.size * pageWidth, color: Color(t.color));

/// Text einer Notiz samt formatierten Teilen.
TextSpan noteSpan(TextNote t, double pageWidth) =>
    richSpan(t.text, charsFromMarks(t.marks, t.text.length), noteStyle(t, pageWidth));

/// Fläche einer Text-Notiz auf der Seite (für den Radierer).
Rect textNoteBounds(TextNote t, Size size) {
  final painter = TextPainter(text: noteSpan(t, size.width), textDirection: TextDirection.ltr)..layout();
  final r = Offset(t.x * size.width, t.y * size.height) & painter.size;
  painter.dispose();
  return r;
}

/// Malt eine Text-Notiz direkt (für die Lasso-Auswahl), so wie sie auch
/// als Widget erscheint.
void paintTextNote(Canvas canvas, TextNote t, Size size) {
  final painter = TextPainter(text: noteSpan(t, size.width), textDirection: TextDirection.ltr)..layout();
  final origin = Offset(t.x * size.width, t.y * size.height);
  if (t.background != TextNote.noBackground) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(origin.dx, origin.dy, painter.width + 4, painter.height),
        const Radius.circular(3),
      ),
      Paint()..color = Color(t.background),
    );
  }
  painter.paint(canvas, origin + const Offset(2, 0));
  painter.dispose();
}

/// Zeigt die Text-Notizen einer Seite. Im Text-Modus kann man tippen, um eine
/// Notiz zu schreiben, eine vorhandene antippen, um sie zu ändern, oder sie
/// mit dem Finger, Stift oder der Maus verschieben.
class TextNotesLayer extends StatefulWidget {
  const TextNotesLayer({
    super.key,
    required this.page,
    required this.controller,
    required this.tools,
    required this.onEditingChanged,
  });

  final int page;
  final InkController controller;
  final ToolController tools;

  /// Meldet, ob gerade getippt wird (dann blättern Tasten nicht um).
  final ValueChanged<bool> onEditingChanged;

  @override
  State<TextNotesLayer> createState() => _TextNotesLayerState();
}

class _TextNotesLayerState extends State<TextNotesLayer> {
  /// Position der Notiz, die gerade bearbeitet wird (normiert).
  Offset? _editAt;

  /// ID der bearbeiteten Notiz (null = neue Notiz).
  String? _editId;

  final _text = RichNoteController();
  final _focus = FocusNode();

  /// Verschieben: ID und aktuelle Verschiebung in Pixeln.
  String? _dragId;
  Offset _dragDelta = Offset.zero;

  InkController get c => widget.controller;
  ToolController get tools => widget.tools;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editAt != null) _commit();
    });
  }

  @override
  void didUpdateWidget(TextNotesLayer old) {
    super.didUpdateWidget(old);
    if (old.page != widget.page && _editAt != null) _commit();
  }

  @override
  void dispose() {
    // Ungespeicherten Text noch übernehmen – erst nach dem Abbau, weil die
    // Anzeige währenddessen nicht verändert werden darf.
    final at = _editAt, id = _editId, text = _text.text, marks = _text.marks, page = widget.page, ctrl = c;
    if (tools.richText.value?.controller == _text) tools.richText.value = null;
    final st = tools.textStyle;
    if (at != null) {
      Future.microtask(() {
        if (ctrl.isDisposed) return;
        id == null
            ? ctrl.addText(
                page: page,
                x: at.dx,
                y: at.dy,
                text: text,
                size: st.size,
                color: st.color,
                background: st.background,
                font: st.font,
                bold: st.bold,
                italic: st.italic,
                marks: marks,
              )
            : ctrl.updateText(
                id,
                text: text,
                size: st.size,
                color: st.color,
                background: st.background,
                font: st.font,
                bold: st.bold,
                italic: st.italic,
                marks: marks,
              );
      });
    }
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEditing(Offset normalized, {TextNote? existing}) {
    // Das Einstellungsfenster zeigt den Stil der angetippten Notiz; Änderungen
    // dort gelten dann für diese Notiz.
    if (existing != null) {
      tools.setTextStyle(
        tools.textStyle.copyWith(
          size: existing.size,
          color: existing.color,
          background: existing.background,
          font: existing.font,
          bold: existing.bold,
          italic: existing.italic,
        ),
        save: false,
      );
    }
    setState(() {
      _editAt = existing == null ? normalized : Offset(existing.x, existing.y);
      _editId = existing?.id;
      _text.load(existing?.text ?? '', existing?.marks ?? const []);
    });
    // Das Text-Fenster formatiert ab jetzt markierte Teile dieser Notiz.
    tools.richText.value = RichTextTarget(
      _text,
      baseBold: () => tools.textStyle.bold,
      baseItalic: () => tools.textStyle.italic,
    );
    widget.onEditingChanged(true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _commit() {
    final at = _editAt;
    if (at == null) return;
    final text = _text.text;
    final marks = _text.marks;
    final id = _editId;
    setState(() {
      _editAt = null;
      _editId = null;
    });
    if (tools.richText.value?.controller == _text) tools.richText.value = null;
    final st = tools.textStyle;
    if (id == null) {
      c.addText(
        page: widget.page,
        x: at.dx,
        y: at.dy,
        text: text,
        size: st.size,
        color: st.color,
        background: st.background,
        font: st.font,
        bold: st.bold,
        italic: st.italic,
        marks: marks,
      );
    } else {
      c.updateText(
        id,
        text: text,
        size: st.size,
        color: st.color,
        background: st.background,
        font: st.font,
        bold: st.bold,
        italic: st.italic,
        marks: marks,
      );
    }
    widget.onEditingChanged(false);
  }

  void _format({bool bold = false, bool italic = false, bool underline = false}) {
    final t = tools.richText.value;
    final st = tools.textStyle;
    if (t != null && t.hasSelection) {
      if (bold) t.toggleBold();
      if (italic) t.toggleItalic();
      if (underline) t.toggleUnderline();
    } else if (bold || italic) {
      tools.setTextStyle(st.copyWith(bold: bold ? !st.bold : null, italic: italic ? !st.italic : null));
    } else if (underline) {
      _text.selection = TextSelection(baseOffset: 0, extentOffset: _text.text.length);
      t?.toggleUnderline();
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
    }
  }

  void _cancel() {
    if (tools.richText.value?.controller == _text) tools.richText.value = null;
    setState(() {
      _editAt = null;
      _editId = null;
    });
    widget.onEditingChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return ListenableBuilder(
          listenable: Listenable.merge([c, tools, tools.selection]),
          builder: (context, _) {
            final active = tools.mode == ToolMode.text;
            // Ausgewählte Notizen malt die Lasso-Auswahl (sie bewegen sich mit).
            final sel = tools.selection.value;
            final hidden = sel != null && sel.isOn(c, widget.page) ? sel.ids.texts : const <String>{};
            final notes = c.annotations.visibleTextsOn(widget.page).where((n) => !hidden.contains(n.id));
            return Stack(
              fit: StackFit.expand,
              children: [
                // Leere Fläche: Tippen = neue Notiz (nur im Text-Modus).
                if (active)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      if (_editAt != null) {
                        _commit();
                        return;
                      }
                      _startEditing(Offset(d.localPosition.dx / size.width, d.localPosition.dy / size.height));
                    },
                  ),
                for (final n in notes)
                  if (n.id != _editId) _buildNote(n, size, active),
                if (_editAt != null) _buildEditor(size),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildNote(TextNote n, Size size, bool active) {
    final dragging = n.id == _dragId;
    final left = n.x * size.width + (dragging ? _dragDelta.dx : 0);
    final top = n.y * size.height + (dragging ? _dragDelta.dy : 0);
    final label = Text.rich(noteSpan(n, size.width));
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        ignoring: !active,
        child: MouseRegion(
          cursor: active ? SystemMouseCursors.move : MouseCursor.defer,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _startEditing(Offset.zero, existing: n),
            onPanStart: (_) => setState(() {
              _dragId = n.id;
              _dragDelta = Offset.zero;
            }),
            onPanUpdate: (d) => setState(() => _dragDelta += d.delta),
            onPanEnd: (_) {
              final nx = ((n.x * size.width + _dragDelta.dx) / size.width).clamp(0.0, 0.98);
              final ny = ((n.y * size.height + _dragDelta.dy) / size.height).clamp(0.0, 0.98);
              setState(() => _dragId = null);
              c.updateText(n.id, x: nx, y: ny);
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: n.background == TextNote.noBackground ? null : Color(n.background),
                border: active ? Border.all(color: VoltiColors.seafoam.withValues(alpha: 0.35)) : null,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: label),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditor(Size size) {
    final at = _editAt!;
    // Stil aus dem Text-Werkzeug – Änderungen im Fenster sieht man sofort.
    final st = tools.textStyle;
    final style = voltiTextStyle(
      font: st.font,
      bold: st.bold,
      italic: st.italic,
      fontSize: st.size * size.width,
      color: Color(st.color),
    );
    final left = at.dx * size.width;
    return Positioned(
      left: left,
      top: at.dy * size.height,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: 140, maxWidth: (size.width - left).clamp(140, size.width)),
        child: IntrinsicWidth(
          child: CallbackShortcuts(
            bindings: {
              // Enter = fertig, Umschalt+Enter = neue Zeile, Esc = abbrechen.
              const SingleActivator(LogicalKeyboardKey.enter): _commit,
              const SingleActivator(LogicalKeyboardKey.numpadEnter): _commit,
              const SingleActivator(LogicalKeyboardKey.escape): _cancel,
              // Wie in Word: Strg+B/I/U für den markierten Teil (sonst die ganze Notiz).
              const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => _format(bold: true),
              const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _format(italic: true),
              const SingleActivator(LogicalKeyboardKey.keyU, control: true): () => _format(underline: true),
            },
            child: TextField(
              controller: _text,
              focusNode: _focus,
              style: style,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              cursorColor: style.color,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: st.background == TextNote.noBackground ? const Color(0xE6FFFFFF) : Color(st.background),
                hintText: 'Notiz …',
                hintStyle: style.copyWith(color: const Color(0x66000000)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: VoltiColors.seafoam),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: VoltiColors.seafoam, width: 1.5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
