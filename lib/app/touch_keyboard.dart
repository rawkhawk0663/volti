import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Bildschirmtastatur unter Windows.
///
/// Windows blendet die Bildschirmtastatur bei Flutter-Apps nicht von selbst
/// ein. Volti meldet deshalb, wenn ein Textfeld mit dem Finger oder dem Stift
/// angetippt wird. Gezeigt wird sie nur, wenn keine Tastatur angeschlossen ist
/// (Tablet-Modus) – das prüft der Windows-Teil (`flutter_window.cpp`).
/// Mit der Maus oder am Computer mit Tastatur erscheint sie nie.
class TouchKeyboard {
  TouchKeyboard._();

  static const _channel = MethodChannel('volti/keyboard');
  static bool _installed = false;

  static PointerDeviceKind? _lastKind;
  static DateTime _lastDown = DateTime(2000);
  static Offset _downAt = Offset.zero;
  static bool _textFocused = false;
  static bool _focusedBeforeDown = false;
  static bool _shown = false;
  static Timer? _hideTimer;

  static void install() {
    if (_installed || !Platform.isWindows) return;
    _installed = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    FocusManager.instance.addListener(_onFocus);
  }

  static bool _byHand(PointerDeviceKind? k) =>
      k == PointerDeviceKind.touch || k == PointerDeviceKind.stylus || k == PointerDeviceKind.invertedStylus;

  /// Hat gerade ein Textfeld den Fokus? (Dessen Fokus sitzt in einem EditableText.)
  static BuildContext? _focusedText() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null || !ctx.mounted) return null;
    if (ctx.widget is EditableText) return ctx;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null ? ctx : null;
  }

  static void _onPointer(PointerEvent e) {
    if (e is PointerDownEvent) {
      _lastKind = e.kind;
      _lastDown = DateTime.now();
      _downAt = e.position;
      _focusedBeforeDown = _focusedText() != null;
    } else if (e is PointerUpEvent && _byHand(e.kind) && _focusedBeforeDown) {
      // Nochmals in ein schon aktives Textfeld getippt (z. B. nachdem man die
      // Tastatur weggewischt hat): wieder zeigen – aber nur, wenn es das
      // Textfeld selbst war und kein Knopf daneben.
      final ctx = _focusedText();
      if (ctx == null || (e.position - _downAt).distance > kTouchSlop) return;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.attached) return;
      final rect = (box.localToGlobal(Offset.zero) & box.size).inflate(12);
      if (rect.contains(e.position)) _show();
    }
  }

  static void _onFocus() {
    final focused = _focusedText() != null;
    if (focused == _textFocused) return;
    _textFocused = focused;
    if (focused) {
      _hideTimer?.cancel();
      final recent = DateTime.now().difference(_lastDown) < const Duration(seconds: 2);
      if (_byHand(_lastKind) && recent) _show();
    } else if (_shown) {
      // Kurz warten: Springt der Fokus nur ins nächste Textfeld, bleibt sie.
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(milliseconds: 250), () {
        if (_focusedText() == null) _hide();
      });
    }
  }

  static Future<void> _show() async {
    try {
      final ok = await _channel.invokeMethod<bool>('show');
      if (ok == true) _shown = true;
    } catch (_) {
      // Ältere Windows-Version o. ä.: dann eben ohne.
    }
  }

  static Future<void> _hide() async {
    _shown = false;
    try {
      await _channel.invokeMethod<bool>('hide');
    } catch (_) {}
  }
}
