import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ink/tab_block.dart';
import '../../core/ink/tool_settings.dart';
import 'ink_controller.dart';
import 'shapes.dart';
import 'tab_keys.dart';
import 'tab_paint.dart';
import 'tab_session.dart';
import 'tool_controller.dart';
import '../../app/l10n.dart';

/// Zeigt die Tabulaturen einer Seite. Mit dem Werkzeug „Tabulatur“:
///
/// * Mit Stift oder Maus ziehen (oder tippen) legt eine neue an – wie die Form
///   „Tabulatur“: nur waagrecht gezogen übliche Höhe, nach unten gezogen höher.
/// * Eine vorhandene antippen setzt den Cursor dorthin; dann schreibt man mit
///   der Tastatur oder dem Zahlenfeld im Werkzeugfenster.
/// * Griff links oben verschiebt, Griff rechts ändert die Breite.
class TabLayer extends StatefulWidget {
  const TabLayer({
    super.key,
    required this.page,
    required this.controller,
    required this.tools,
    required this.onEditingChanged,
  });

  final int page;
  final InkController controller;
  final ToolController tools;

  /// Meldet, ob gerade geschrieben wird (dann blättern Tasten nicht um).
  final ValueChanged<bool> onEditingChanged;

  @override
  State<TabLayer> createState() => _TabLayerState();
}

class _TabLayerState extends State<TabLayer> {
  final _focus = FocusNode(debugLabel: 'tab');

  /// Neue Tabulatur wird gerade aufgezogen (Start und aktuelle Stelle).
  Offset? _dragFrom, _dragTo;

  /// Verschieben bzw. Breite ändern: bisherige Verschiebung in Pixeln.
  Offset _moveDelta = Offset.zero;
  double _widthDelta = 0;

  /// Markieren durch Ziehen über eine Tabulatur: ihre ID und der Anfang.
  ({String id, int from})? _selecting;

  /// Taktstrich, der gerade gezogen wird, und seine Stelle in Pixeln.
  int? _barIndex;
  double _barX = 0;

  /// Die bearbeitete Tabulatur, mit dem gerade gezogenen Taktstrich an der
  /// neuen Stelle (nur Anzeige, gespeichert wird beim Loslassen).
  TabBlock _preview(TabBlock t, Size size) {
    final i = _barIndex;
    if (i == null || i >= t.beats.length || !t.beats[i].bar) return t;
    final l = layoutTab(t, size);
    final beats = [...t.beats];
    // Die Art (Wiederholung, Schlussstrich …) bleibt beim Verschieben.
    beats[i] = TabBeat.bar(at: l.fractionAt(_barX), kind: t.beats[i].kind, meter: t.beats[i].meter);
    return t.copyWith(beats: beats);
  }

  /// Wie weit ein Taktstrich gezogen werden darf: nicht über die Nachbarn
  /// (vorheriger bzw. nächster Taktstrich, Anfang und Ende) hinaus.
  (double, double) _barLimits(TabBlock t, TabLayout l, int i) {
    var lo = l.contentStart, hi = l.contentEnd;
    for (var k = i - 1; k >= 0; k--) {
      if (t.beats[k].bar) {
        lo = l.xs[k];
        break;
      }
    }
    for (var k = i + 1; k < t.beats.length; k++) {
      if (t.beats[k].bar) {
        hi = l.xs[k];
        break;
      }
    }
    return (lo + l.gap * 1.5, math.max(lo + l.gap * 1.5, hi - l.gap * 1.5));
  }

  bool _reported = false;

  InkController get c => widget.controller;
  ToolController get tools => widget.tools;

  TabSession? get _session {
    final s = tools.tabSession.value;
    return s != null && identical(s.ink, c) && s.page == widget.page ? s : null;
  }

  @override
  void initState() {
    super.initState();
    tools.tabSession.addListener(_sessionChanged);
  }

  @override
  void didUpdateWidget(TabLayer old) {
    super.didUpdateWidget(old);
    if (old.tools != widget.tools) {
      old.tools.tabSession.removeListener(_sessionChanged);
      widget.tools.tabSession.addListener(_sessionChanged);
    }
  }

  @override
  void dispose() {
    tools.tabSession.removeListener(_sessionChanged);
    if (_session != null) {
      // Abbau: erst danach beenden (während des Abbaus nichts ändern).
      final t = tools;
      Future.microtask(() => t.tabSession.value = null);
    }
    if (_reported) {
      final cb = widget.onEditingChanged;
      Future.microtask(() => cb(false));
    }
    _focus.dispose();
    super.dispose();
  }

  void _sessionChanged() {
    final mine = _session != null;
    if (mine != _reported) {
      _reported = mine;
      widget.onEditingChanged(mine);
    }
    if (mine) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _session != null) _focus.requestFocus();
      });
    }
    if (mounted) setState(() {});
  }

  void _start(TabBlock t, {int beat = 0, int string = 0}) {
    tools.tabSession.value = TabSession(ink: c, id: t.id, page: widget.page, beat: beat, string: string);
  }

  void _finish() => tools.tabSession.value = null;

  /// Getroffene Tabulatur (oberste zuerst).
  TabBlock? _hit(Offset p, Size size) {
    for (final t in c.annotations.visibleTabsOn(widget.page).reversed) {
      if (layoutTab(t, size).bounds.contains(p)) return t;
    }
    return null;
  }

  void _tapUp(TapUpDetails d, Size size) {
    final t = _hit(d.localPosition, size);
    if (t != null) {
      final l = layoutTab(t, size);
      final slot = l.slotAt(d.localPosition.dx);
      final s = _session;
      if (s != null && s.id == t.id) {
        s.moveTo(slot, l.stringAt(d.localPosition.dy));
      } else {
        _start(t, beat: slot, string: l.stringAt(d.localPosition.dy));
      }
      return;
    }
    if (_session != null) {
      _finish();
      return;
    }
    // Neue Tabulatur nur mit Stift oder Maus (der Finger zeichnet nie).
    if (d.kind == PointerDeviceKind.touch) return;
    final x = d.localPosition.dx;
    _create(
      Offset(x, d.localPosition.dy),
      Offset(math.max(x + size.width * 0.3, size.width * 0.95), d.localPosition.dy),
      size,
    );
  }

  /// Wie die Form „Tabulatur“: Länge vom Ziehen nach links/rechts, Höhe vom
  /// deutlichen Ziehen nach unten.
  void _create(Offset a, Offset b, Size size) {
    final geo = shapeGeometry(ShapeKind.tab, a, b, 1, pageWidth: size.width);
    if (geo.length != TabBlock.strings) return;
    final top = math.min(geo.first.points.first.dy, geo.last.points.first.dy);
    final bottom = math.max(geo.first.points.first.dy, geo.last.points.first.dy);
    final left = math.min(a.dx, b.dx), right = math.max(a.dx, b.dx);
    // Nur waagrecht gezogen (übliche Höhe): die im Fenster gewählte Grösse.
    var gap = (bottom - top) / (TabBlock.strings - 1) / size.width;
    if ((gap - TabBlock.defaultGap).abs() < 1e-6) gap = tools.tabGap;
    final id = c.addTab(
      page: widget.page,
      x: left / size.width,
      y: top / size.height,
      width: (right - left) / size.width,
      gap: gap,
      background: tools.tabBackground,
      meter: tools.tabMeter,
    );
    final t = c.annotations.tab(id);
    if (t != null) _start(t);
  }

  /// Markierte Schläge in die Zwischenablage (Ausschneiden: danach weg).
  void _copy(TabSession s, {bool cut = false}) {
    final clip = s.copy();
    if (clip.isEmpty) return;
    tools.tabClip = clip;
    if (cut) {
      s.hasSelection ? s.deleteSelection() : s.perform(TabAction.deleteBeat);
    }
  }

  void _paste(TabSession s) {
    final clip = tools.tabClip;
    if (clip != null) s.paste(clip);
  }

  void _resetBar(TabBlock t, int i) {
    if (i >= t.beats.length || t.beats[i].at == null) return;
    final beats = [...t.beats];
    beats[i] = TabBeat.bar(kind: t.beats[i].kind, meter: t.beats[i].meter);
    c.updateTab(t.id, beats: beats);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final s = _session;
    if (s == null) return KeyEventResult.ignored;
    if (e is KeyUpEvent) return KeyEventResult.handled;
    final hk = HardwareKeyboard.instance;
    final ctrl = hk.isControlPressed || hk.isMetaPressed;
    final shift = hk.isShiftPressed, alt = hk.isAltPressed;
    final k = e.logicalKey;
    // Rückgängig/Wiederholen gehen auch beim Schreiben.
    if (ctrl && !alt && k == LogicalKeyboardKey.keyZ) {
      shift ? c.redo() : c.undo();
      return KeyEventResult.handled;
    }
    if (ctrl && !alt && k == LogicalKeyboardKey.keyY) {
      c.redo();
      return KeyEventResult.handled;
    }
    // Kopieren, Ausschneiden, Einfügen, alles markieren (fest belegt).
    if (ctrl && !alt && !shift) {
      if (k == LogicalKeyboardKey.keyC || k == LogicalKeyboardKey.keyX) {
        _copy(s, cut: k == LogicalKeyboardKey.keyX);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyV) {
        _paste(s);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyA) {
        s.selectAll();
        return KeyEventResult.handled;
      }
    }
    final action = tools.tabKeys.actionFor(k, ctrl: ctrl, shift: shift, alt: alt);
    // Umschalt + ← / → markiert (wenn die Kombination nicht anders belegt ist).
    if (action == null && shift && !ctrl && !alt) {
      final plain = tools.tabKeys.actionFor(k, ctrl: false, shift: false, alt: false);
      if (plain == TabAction.left || plain == TabAction.right) {
        s.extend(plain == TabAction.left ? -1 : 1);
        return KeyEventResult.handled;
      }
      // Umschalt + ↑ / ↓: den ganzen Schlag markieren (alle Noten
      // übereinander), Entf löscht ihn dann.
      if (plain == TabAction.up || plain == TabAction.down) {
        s.selectColumn();
        return KeyEventResult.handled;
      }
    }
    // Rücktaste löscht wie „Bundzahl löschen“ (falls nicht anders belegt).
    if (action == null && k == LogicalKeyboardKey.backspace && !ctrl && !alt) {
      s.perform(TabAction.clearNote);
      return KeyEventResult.handled;
    }
    if (action != null) {
      if (!s.perform(action)) _finish();
      return KeyEventResult.handled;
    }
    final d = digitOf(k);
    if (d != null && !ctrl && !alt) {
      s.digit(d);
      return KeyEventResult.handled;
    }
    // Alle anderen Tasten schlucken: Sie sollen weder umblättern noch
    // Werkzeuge wechseln.
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return ListenableBuilder(
          listenable: Listenable.merge([c, tools, ?_session]),
          builder: (context, _) {
            final active = tools.mode == ToolMode.tab;
            final session = _session;
            final tabs = c.annotations.visibleTabsOn(widget.page);
            final editing = session?.block;
            return Focus(
              focusNode: _focus,
              onKeyEvent: _onKey,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _TabsPainter(
                          tabs,
                          preview: editing == null ? null : _preview(editing, size),
                          moving: editing?.id,
                          moveDelta: _moveDelta,
                          widthDelta: _widthDelta,
                          dragging: _barIndex != null || _moveDelta != Offset.zero || _widthDelta != 0,
                        ),
                      ),
                    ),
                  ),
                  if (active)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // Die Tabulatur beginnt dort, wo der Stift aufsetzt.
                      dragStartBehavior: DragStartBehavior.down,
                      onTapUp: (d) => _tapUp(d, size),
                      onPanStart: (d) {
                        if (d.kind == PointerDeviceKind.touch) return;
                        // Auf einer Tabulatur: markieren statt neu anlegen.
                        final hit = _hit(d.localPosition, size);
                        if (hit != null) {
                          final l = layoutTab(hit, size);
                          final slot = l.slotAt(d.localPosition.dx);
                          if (_session?.id != hit.id) _start(hit, beat: slot, string: l.stringAt(d.localPosition.dy));
                          _selecting = (id: hit.id, from: slot);
                          _session?.selectRange(slot, slot);
                          return;
                        }
                        setState(() => _dragFrom = _dragTo = d.localPosition);
                      },
                      onPanUpdate: (d) {
                        final sel = _selecting;
                        if (sel != null) {
                          final t = c.annotations.tab(sel.id);
                          if (t != null) {
                            _session?.selectRange(sel.from, layoutTab(t, size).slotAt(d.localPosition.dx));
                          }
                          return;
                        }
                        if (_dragFrom != null) setState(() => _dragTo = d.localPosition);
                      },
                      onPanEnd: (_) {
                        if (_selecting != null) {
                          _selecting = null;
                          return;
                        }
                        final a = _dragFrom, b = _dragTo;
                        setState(() => _dragFrom = _dragTo = null);
                        if (a != null && b != null) {
                          _finish();
                          _create(a, b, size);
                        }
                      },
                    ),
                  if (_dragFrom != null && _dragTo != null)
                    IgnorePointer(child: CustomPaint(painter: _PreviewPainter(_dragFrom!, _dragTo!, size.width))),
                  if (session != null && editing != null) ..._editingOverlay(session, editing, size),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _editingOverlay(TabSession s, TabBlock saved, Size size) {
    final t = _preview(saved, size);
    final l = layoutTab(t, size);
    final scheme = Theme.of(context).colorScheme;
    final g = l.gap;
    final handle = math.max(22.0, g * 1.8);
    return [
      // Takte mit falscher Länge (zu voll oder zu leer) leicht rot.
      if (t.measure != null || t.beats.any((b) => b.meter != null))
        IgnorePointer(
          child: CustomPaint(painter: _MeasureCheckPainter(t, l, scheme.error, offset: _moveDelta)),
        ),
      IgnorePointer(
        child: CustomPaint(
          painter: _CursorPainter(
            layout: l,
            beat: s.beat,
            string: s.string,
            color: scheme.primary,
            offset: _moveDelta,
            selection: s.selection,
            strings: s.stringSelection,
          ),
        ),
      ),
      // Griff zum Verschieben (links oben)
      Positioned(
        left: l.origin.dx - handle * 0.5 + _moveDelta.dx,
        top: l.top - g * 1.2 - handle + _moveDelta.dy,
        width: handle,
        height: handle,
        child: _Handle(
          icon: Icons.open_with,
          tooltip: tr('Tabulatur verschieben', 'Move tablature'),
          cursor: SystemMouseCursors.move,
          onDrag: (d) => setState(() => _moveDelta += d),
          onEnd: () {
            final dx = _moveDelta.dx / size.width, dy = _moveDelta.dy / size.height;
            setState(() => _moveDelta = Offset.zero);
            c.updateTab(t.id, x: (t.x + dx).clamp(0.0, 0.98), y: (t.y + dy).clamp(0.0, 0.98));
          },
        ),
      ),
      // Griffe an den Taktstrichen: ziehen verschiebt den Taktstrich, die
      // Schläge davor und danach verteilen sich neu. Lange drücken (oder
      // Rechtsklick) = wieder automatisch.
      for (var i = 0; i < t.beats.length; i++)
        if (t.beats[i].bar)
          Positioned(
            left: l.lineXs[i] - handle * 0.4 + _moveDelta.dx,
            top: l.top - g * 0.9 - handle * 0.8 + _moveDelta.dy,
            width: handle * 0.8,
            height: handle * 0.8,
            child: GestureDetector(
              onLongPress: () => _resetBar(saved, i),
              onSecondaryTap: () => _resetBar(saved, i),
              child: _Handle(
                icon: Icons.swap_horiz,
                tooltip: tr(
                  'Taktstrich verschieben (lange drücken: wieder automatisch)',
                  'Move bar line (long-press: automatic again)',
                ),
                cursor: SystemMouseCursors.resizeLeftRight,
                small: true,
                filled: t.beats[i].at != null,
                onDrag: (d) {
                  final base = layoutTab(saved, size);
                  final (lo, hi) = _barLimits(saved, base, i);
                  setState(() {
                    if (_barIndex != i) {
                      _barIndex = i;
                      _barX = base.xs[i];
                    }
                    _barX = (_barX + d.dx).clamp(lo, hi);
                  });
                },
                onEnd: () {
                  final moved = _preview(saved, size);
                  setState(() => _barIndex = null);
                  c.updateTab(saved.id, beats: moved.beats);
                },
              ),
            ),
          ),
      // Griff für die Breite (rechts)
      Positioned(
        left: l.endX + _widthDelta - handle * 0.5,
        top: (l.top + l.bottom) / 2 - handle / 2,
        width: handle,
        height: handle,
        child: _Handle(
          icon: Icons.swap_horiz,
          tooltip: tr('Breite ändern', 'Change width'),
          cursor: SystemMouseCursors.resizeLeftRight,
          onDrag: (d) => setState(() => _widthDelta += d.dx),
          onEnd: () {
            final w = (l.endX - l.origin.dx + _widthDelta) / size.width;
            setState(() => _widthDelta = 0);
            c.updateTab(t.id, width: w.clamp(0.08, 1.0 - t.x));
          },
        ),
      ),
    ];
  }
}

class _Handle extends StatelessWidget {
  const _Handle({
    this.small = false,
    this.filled = true,
    required this.icon,
    required this.tooltip,
    required this.cursor,
    required this.onDrag,
    required this.onEnd,
  });
  final IconData icon;
  final String tooltip;
  final MouseCursor cursor;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onEnd;

  /// Kleiner Griff (Taktstriche).
  final bool small;

  /// Ausgefüllt; sonst nur umrandet (Taktstrich noch automatisch).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      // Nur beim Darüberfahren mit der Maus: langes Drücken ist der Rechtsklick.
      triggerMode: TooltipTriggerMode.manual,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) => onDrag(d.delta),
          onPanEnd: (_) => onEnd(),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: filled ? scheme.primary : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: filled ? Colors.white : scheme.primary, width: 1.5),
            ),
            child: Icon(icon, color: filled ? Colors.white : scheme.primary, size: small ? 11 : 14),
          ),
        ),
      ),
    );
  }
}

class _TabsPainter extends CustomPainter {
  _TabsPainter(
    this.tabs, {
    this.preview,
    this.moving,
    this.moveDelta = Offset.zero,
    this.widthDelta = 0,
    this.dragging = false,
  });
  final List<TabBlock> tabs;

  /// Wird die Tabulatur gerade verschoben (oder ein Taktstrich)? Dann ist ihr
  /// Hintergrund höchstens zu 75 % deckend – man sieht, was darunter liegt.
  final bool dragging;
  static const _dragAlpha = 0.75;

  /// Bearbeitete Tabulatur mit Änderungen, die noch nicht gespeichert sind.
  final TabBlock? preview;
  final String? moving;
  final Offset moveDelta;
  final double widthDelta;

  @override
  void paint(Canvas canvas, Size size) {
    for (final saved in tabs) {
      final t = preview != null && preview!.id == saved.id ? preview! : saved;
      var shown = t;
      if (t.id == moving && (moveDelta != Offset.zero || widthDelta != 0)) {
        shown = t.copyWith(
          x: t.x + moveDelta.dx / size.width,
          y: t.y + moveDelta.dy / size.height,
          width: math.max(0.08, t.width + widthDelta / size.width),
        );
      }
      final bg = shown.background;
      if (t.id == moving && dragging && bg != TabBlock.noBackground && (bg >>> 24) / 255 > _dragAlpha) {
        shown = shown.copyWith(background: ((_dragAlpha * 255).round() << 24) | (bg & 0xFFFFFF));
      }
      paintTabBlock(canvas, shown, size);
    }
  }

  @override
  bool shouldRepaint(_TabsPainter old) =>
      !identical(old.tabs, tabs) ||
      !identical(old.preview, preview) ||
      old.moving != moving ||
      old.moveDelta != moveDelta ||
      old.widthDelta != widthDelta ||
      old.dragging != dragging;
}

/// Cursor: Kästchen auf Saite und Schlag, dazu die Spalte leicht hervorgehoben.
class _CursorPainter extends CustomPainter {
  _CursorPainter({
    required this.layout,
    required this.beat,
    required this.string,
    required this.color,
    this.offset = Offset.zero,
    this.selection,
    this.strings,
  });
  final TabLayout layout;
  final int beat, string;
  final Color color;
  final Offset offset;

  /// Markierte Einträge (beide inklusive).
  final (int, int)? selection;

  /// Markierte Saiten (beide inklusive), null = alle.
  final (int, int)? strings;

  @override
  void paint(Canvas canvas, Size size) {
    final l = layout;
    final g = l.gap;
    final sel = selection;
    if (sel != null && sel.$2 < l.xs.length) {
      final left = l.xs[sel.$1] - l.slotWidths[sel.$1] / 2;
      final right = l.xs[sel.$2] + l.slotWidths[sel.$2] / 2;
      final ss = strings;
      final r = (ss == null
              ? Rect.fromLTRB(left, l.top - g * 0.7, right, l.stemBottom)
              : Rect.fromLTRB(left, l.lineY(ss.$1) - g * 0.55, right, l.lineY(ss.$2) + g * 0.55))
          .shift(offset);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(g * 0.3)),
        Paint()..color = color.withValues(alpha: 0.22),
      );
    }
    final i = beat.clamp(0, l.xs.length - 1);
    final cx = l.xs[i] + offset.dx;
    final w = math.max(l.slotWidths[i] * 0.9, g * 1.5);
    final column = Rect.fromLTRB(cx - w / 2, l.top - g * 0.7 + offset.dy, cx + w / 2, l.stemBottom + offset.dy);
    canvas.drawRRect(
      RRect.fromRectAndRadius(column, Radius.circular(g * 0.3)),
      Paint()..color = color.withValues(alpha: 0.08),
    );
    final cell = Rect.fromCenter(center: Offset(cx, l.lineY(string) + offset.dy), width: w, height: g * 1.15);
    final r = RRect.fromRectAndRadius(cell, Radius.circular(g * 0.25));
    canvas.drawRRect(r, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawRRect(
      r,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, g * 0.12),
    );
  }

  @override
  bool shouldRepaint(_CursorPainter old) =>
      old.beat != beat ||
      old.string != string ||
      old.layout != layout ||
      old.offset != offset ||
      old.color != color ||
      old.selection != selection ||
      old.strings != strings;
}

/// Vorschau beim Aufziehen einer neuen Tabulatur.
class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.a, this.b, this.pageWidth);
  final Offset a, b;
  final double pageWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x997A3CF0)
      ..strokeWidth = 1.2;
    for (final piece in shapeGeometry(ShapeKind.tab, a, b, 1, pageWidth: pageWidth)) {
      canvas.drawLine(piece.points.first, piece.points.last, paint);
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.a != a || old.b != b;
}

/// Markiert Takte, deren Notenwerte nicht zur Taktart passen. Der letzte Takt
/// darf noch zu kurz sein (dort wird gerade geschrieben).
class _MeasureCheckPainter extends CustomPainter {
  _MeasureCheckPainter(this.t, this.l, this.color, {this.offset = Offset.zero});
  final TabBlock t;
  final TabLayout l;
  final Color color;
  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) {
    final all = measuresOf(t.beats);
    final lengths = measureLengths(t.beats, t.measure);
    final g = l.gap;
    for (final (i, part) in all.indexed) {
      final m = lengths[i];
      if (m == null || part.end <= part.start) continue;
      final last = i == all.length - 1;
      final wrong = (part.length - m).abs() > 1e-6 && !(last && part.length < m);
      if (!wrong) continue;
      final left = l.xs[part.start] - l.slotWidths[part.start] / 2;
      final right = l.xs[part.end - 1] + l.slotWidths[part.end - 1] / 2;
      final r = Rect.fromLTRB(left, l.top - g * 0.6, right, l.stemBottom + g * 0.2).shift(offset);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(g * 0.3)),
        Paint()..color = color.withValues(alpha: 0.13),
      );
    }
  }

  @override
  bool shouldRepaint(_MeasureCheckPainter old) => !identical(old.t, t) || old.offset != offset || old.color != color;
}
