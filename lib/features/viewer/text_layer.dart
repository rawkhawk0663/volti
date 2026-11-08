import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ink/text_note.dart';
import 'ink_controller.dart';

/// Schriftstil einer Text-Notiz auf einer Seite der Breite [pageWidth].
TextStyle noteStyle(TextNote t, double pageWidth) =>
    TextStyle(fontSize: t.size * pageWidth, color: Color(t.color), height: 1.2, fontWeight: FontWeight.w500);

/// Fläche einer Text-Notiz auf der Seite (für den Radierer).
Rect textNoteBounds(TextNote t, Size size) {
  final painter = TextPainter(
    text: TextSpan(text: t.text, style: noteStyle(t, size.width)),
    textDirection: TextDirection.ltr,
  )..layout();
  final r = Offset(t.x * size.width, t.y * size.height) & painter.size;
  painter.dispose();
  return r;
}

/// Zeigt die Text-Notizen einer Seite. Im Text-Modus kann man tippen, um eine
/// Notiz zu schreiben, eine vorhandene antippen, um sie zu ändern, oder sie
/// mit dem Finger, Stift oder der Maus verschieben.
class TextNotesLayer extends StatefulWidget {
  const TextNotesLayer({super.key, required this.page, required this.controller, required this.onEditingChanged});

  final int page;
  final InkController controller;

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

  final _text = TextEditingController();
  final _focus = FocusNode();

  /// Verschieben: ID und aktuelle Verschiebung in Pixeln.
  String? _dragId;
  Offset _dragDelta = Offset.zero;

  InkController get c => widget.controller;

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
    final at = _editAt, id = _editId, text = _text.text, page = widget.page, ctrl = c;
    if (at != null) {
      Future.microtask(() {
        if (ctrl.isDisposed) return;
        id == null ? ctrl.addText(page: page, x: at.dx, y: at.dy, text: text) : ctrl.updateText(id, text: text);
      });
    }
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEditing(Offset normalized, {TextNote? existing}) {
    setState(() {
      _editAt = existing == null ? normalized : Offset(existing.x, existing.y);
      _editId = existing?.id;
      _text.text = existing?.text ?? '';
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
    });
    widget.onEditingChanged(true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _commit() {
    final at = _editAt;
    if (at == null) return;
    final text = _text.text;
    final id = _editId;
    setState(() {
      _editAt = null;
      _editId = null;
    });
    if (id == null) {
      c.addText(page: widget.page, x: at.dx, y: at.dy, text: text);
    } else {
      c.updateText(id, text: text);
    }
    widget.onEditingChanged(false);
  }

  void _cancel() {
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
          listenable: c,
          builder: (context, _) {
            final active = c.mode == ToolMode.text;
            final notes = c.annotations.visibleTextsOn(widget.page);
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
    final label = Text(n.text, style: noteStyle(n, size.width));
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
              // Leicht heller Hintergrund, damit der Text über Notenlinien lesbar bleibt.
              decoration: BoxDecoration(
                color: const Color(0xC8FFFFFF),
                border: active ? Border.all(color: const Color(0x55B5593A)) : null,
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
    final existing = _editId == null ? null : c.annotations.text(_editId!);
    final style = TextStyle(
      fontSize: (existing?.size ?? c.textSize) * size.width,
      color: Color(existing?.color ?? c.penColor),
      height: 1.2,
      fontWeight: FontWeight.w500,
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
                fillColor: const Color(0xE6FFFFFF),
                hintText: 'Notiz …',
                hintStyle: style.copyWith(color: const Color(0x66000000)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Color(0xFFB5593A)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Color(0xFFB5593A), width: 1.5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
