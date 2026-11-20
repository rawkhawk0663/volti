import 'package:flutter/foundation.dart';

import '../../core/ink/tab_block.dart';
import 'ink_controller.dart';
import 'tab_keys.dart';

/// Gerade wird in dieser Tabulatur geschrieben: Cursor und Änderungen.
///
/// Gemeinsam für Tastatur (in der Tabulatur selbst) und Zahlenfeld (im
/// Werkzeugfenster). Jede Änderung ist ein Rückgängig-Schritt.
class TabSession extends ChangeNotifier {
  TabSession({required this.ink, required this.id, required this.page, int beat = 0, int string = 0})
    : _editor = TabEditor(const [], beat: beat, string: string);

  final InkController ink;
  final String id;

  /// PDF-Seite der Tabulatur.
  final int page;

  final TabEditor _editor;

  /// Die Tabulatur, wie sie gerade gespeichert ist (null = gelöscht).
  TabBlock? get block {
    final t = ink.annotations.tab(id);
    return t == null || t.deleted ? null : t;
  }

  int get beat => _editor.beat.clamp(0, block?.beats.length ?? 0);
  int get string => _editor.string;

  /// Schlag unter dem Cursor (null = freier Platz am Ende).
  TabBeat? get current {
    final b = block;
    if (b == null || beat >= b.beats.length) return null;
    return b.beats[beat];
  }

  /// Änderung ausführen und speichern. Vorher den gespeicherten Stand
  /// übernehmen – nach „Rückgängig“ hat er sich vielleicht geändert.
  void _edit(void Function(TabEditor e) op) {
    final b = block;
    if (b == null) return;
    _editor.beats = [...b.beats];
    _editor.beat = _editor.beat.clamp(0, b.beats.length);
    op(_editor);
    ink.updateTab(id, beats: _editor.beats);
    notifyListeners();
  }

  /// Nur den Cursor bewegen (keine Änderung an der Tabulatur).
  void _move(void Function(TabEditor e) op) {
    final b = block;
    if (b == null) return;
    _editor.beats = [...b.beats];
    op(_editor);
    notifyListeners();
  }

  void moveTo(int beat, int string) => _move((e) {
    e.beat = beat.clamp(0, e.beats.length);
    e.string = string.clamp(0, TabBlock.strings - 1);
  });

  void digit(int d) => _edit((e) => e.digit(d));
  void setFret(int f) => _edit((e) => e.setFret(f));
  void setValue(int v) => _edit((e) => e.setValue(v));

  /// Eine Aktion (Taste oder Knopf). Gibt false zurück bei [TabAction.finish] –
  /// das Beenden erledigt der Aufrufer.
  bool perform(TabAction a) {
    final v = a.noteValue;
    if (v != null) {
      setValue(v);
      return true;
    }
    switch (a) {
      case TabAction.left:
        _move((e) => e.move(-1));
      case TabAction.right:
        _move((e) => e.move(1));
      case TabAction.up:
        _move((e) => e.moveString(-1));
      case TabAction.down:
        _move((e) => e.moveString(1));
      case TabAction.shorter:
        _edit((e) => e.shorter());
      case TabAction.longer:
        _edit((e) => e.shorter(-1));
      case TabAction.dot:
        _edit((e) => e.toggleDot());
      case TabAction.rest:
        _edit((e) => e.rest());
      case TabAction.bar:
        _edit((e) => e.bar());
      case TabAction.clearNote:
        _edit((e) => e.clearNote());
      case TabAction.deleteBeat:
        _edit((e) => e.deleteBeat());
      case TabAction.insertBeat:
        _edit((e) => e.insertBeat());
      case TabAction.finish:
        return false;
      default:
        break;
    }
    return true;
  }
}
