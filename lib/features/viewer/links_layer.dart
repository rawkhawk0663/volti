import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/ink/navigation_marks.dart';
import 'ink_controller.dart';
import 'tool_controller.dart';
import '../../app/l10n.dart';

/// Ziel, das nach einem Sprung kurz orange aufblinkt.
class JumpFlash {
  JumpFlash(this.ink, this.page, this.x, this.y);
  final InkController ink;
  final int page;
  final double x, y;
}

/// Sprungmarken einer Seite: blaue Punkte, die beim Antippen springen.
///
/// Im Werkzeug "Sprung" setzt man mit zwei Tipps eine neue Marke: zuerst den
/// Startpunkt (z. B. beim "D.S."), dann das Ziel – auch nach dem Umblättern.
/// Einen Punkt dort ziehen verschiebt ihn, antippen öffnet ein Menü.
class LinksLayer extends StatelessWidget {
  const LinksLayer({
    super.key,
    required this.page,
    required this.controller,
    required this.tools,
    required this.flash,
    required this.onJump,
  });

  final int page;
  final InkController controller;
  final ToolController tools;
  final ValueListenable<JumpFlash?> flash;
  final ValueChanged<JumpLink> onJump;

  static const _dot = 30.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        return ListenableBuilder(
          listenable: Listenable.merge([controller, tools, tools.linkStart, flash]),
          builder: (context, _) {
            final editing = tools.mode == ToolMode.link;
            final links = controller.annotations.linksOn(page);
            final start = tools.linkStart.value;
            final f = flash.value;
            Offset at(double x, double y) => Offset(x * size.width, y * size.height);
            return Stack(
              fit: StackFit.expand,
              children: [
                if (editing)
                  // Antippen: Startpunkt bzw. Ziel einer neuen Sprungmarke.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      final x = d.localPosition.dx / size.width, y = d.localPosition.dy / size.height;
                      final s = tools.linkStart.value;
                      if (s == null || !identical(s.ink, controller)) {
                        tools.linkStart.value = (ink: controller, page: page, x: x, y: y);
                      } else {
                        controller.addLink(page: s.page, x: s.x, y: s.y, toPage: page, toX: x, toY: y);
                        tools.linkStart.value = null;
                      }
                    },
                  ),
                // Ziele (nur beim Bearbeiten sichtbar)
                if (editing)
                  for (final l in controller.annotations.allLinks)
                    if (!l.deleted && l.toPage == page)
                      Positioned(
                        left: at(l.toX, l.toY).dx - 9,
                        top: at(l.toX, l.toY).dy - 9,
                        child: const IgnorePointer(child: _TargetRing(size: 18)),
                      ),
                // Startpunkt, der auf sein Ziel wartet
                if (start != null && identical(start.ink, controller) && start.page == page)
                  Positioned(
                    left: at(start.x, start.y).dx - _dot / 2,
                    top: at(start.x, start.y).dy - _dot / 2,
                    child: const IgnorePointer(child: _LinkDot(size: _dot, pending: true)),
                  ),
                for (final l in links)
                  Positioned(
                    left: at(l.x, l.y).dx - _dot / 2,
                    top: at(l.x, l.y).dy - _dot / 2,
                    child: _DraggableDot(
                      link: l,
                      editing: editing,
                      pageSize: size,
                      onJump: () => onJump(l),
                      onMoved: (x, y) => controller.updateLink(l.copyWith(x: x, y: y)),
                      onMenu: (pos) => _menu(context, l, pos),
                    ),
                  ),
                // Kurzes oranges Aufblinken am Ziel nach einem Sprung
                if (f != null && identical(f.ink, controller) && f.page == page)
                  Positioned(
                    left: at(f.x, f.y).dx - 40,
                    top: at(f.x, f.y).dy - 40,
                    child: IgnorePointer(child: _Flash(key: ObjectKey(f))),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _menu(BuildContext context, JumpLink l, Offset pos) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem(value: 'jump', child: Text(tr('Springen', 'Jump'))),
        PopupMenuItem(value: 'target', child: Text(tr('Neues Ziel antippen …', 'Tap new target …'))),
        PopupMenuItem(value: 'delete', child: Text(tr('Sprungmarke löschen', 'Delete jump link'))),
      ],
    );
    switch (choice) {
      case 'jump':
        onJump(l);
      case 'target':
        // Alte Marke weg, Startpunkt bleibt: das nächste Antippen setzt das Ziel.
        controller.deleteLink(l.id);
        tools.linkStart.value = (ink: controller, page: l.page, x: l.x, y: l.y);
      case 'delete':
        controller.deleteLink(l.id);
    }
  }
}

class _DraggableDot extends StatefulWidget {
  const _DraggableDot({
    required this.link,
    required this.editing,
    required this.pageSize,
    required this.onJump,
    required this.onMoved,
    required this.onMenu,
  });
  final JumpLink link;
  final bool editing;
  final Size pageSize;
  final VoidCallback onJump;
  final void Function(double x, double y) onMoved;
  final ValueChanged<Offset> onMenu;

  @override
  State<_DraggableDot> createState() => _DraggableDotState();
}

class _DraggableDotState extends State<_DraggableDot> {
  Offset _drag = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final dot = Transform.translate(
      offset: _drag,
      child: const _LinkDot(size: LinksLayer._dot),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Beim Spielen: antippen = springen. Beim Bearbeiten: Menü, ziehen = verschieben.
      onTapUp: (d) => widget.editing ? widget.onMenu(d.globalPosition) : widget.onJump(),
      onLongPressStart: (d) => widget.onMenu(d.globalPosition),
      onPanUpdate: widget.editing ? (d) => setState(() => _drag += d.delta) : null,
      onPanEnd: widget.editing
          ? (_) {
              final s = widget.pageSize, l = widget.link;
              final x = (l.x + _drag.dx / s.width).clamp(0.0, 1.0), y = (l.y + _drag.dy / s.height).clamp(0.0, 1.0);
              setState(() => _drag = Offset.zero);
              widget.onMoved(x, y);
            }
          : null,
      child: dot,
    );
  }
}

/// Blauer Punkt mit Pfeil.
class _LinkDot extends StatelessWidget {
  const _LinkDot({required this.size, this.pending = false});
  final double size;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF1565C0);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: pending ? Colors.white : blue.withValues(alpha: 0.85),
        border: Border.all(color: blue, width: pending ? 2.5 : 2),
      ),
      child: Icon(Icons.turn_right, size: size * 0.6, color: pending ? blue : Colors.white),
    );
  }
}

class _TargetRing extends StatelessWidget {
  const _TargetRing({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0xFFE07B00), width: 2.5),
    ),
  );
}

/// Oranger Kreis, der sich ausdehnt und verblasst (rund 1.5 s).
class _Flash extends StatelessWidget {
  const _Flash({super.key});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 1600),
    builder: (context, t, _) {
      // zweimal pulsieren
      final phase = (t * 2) % 1;
      return SizedBox(
        width: 80,
        height: 80,
        child: Center(
          child: Container(
            width: 20 + 60 * phase,
            height: 20 + 60 * phase,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFE07B00).withValues(alpha: 0.25 * (1 - t)),
              border: Border.all(
                color: const Color(0xFFE07B00).withValues(alpha: (1 - phase) * (1 - t * 0.5)),
                width: 4,
              ),
            ),
          ),
        ),
      );
    },
  );
}
