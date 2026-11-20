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
    _editor.measure = b.measure;
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

  /// Markierte Einträge (Bereich, beide inklusive) oder null.
  (int, int)? get selection {
    final b = block;
    if (b == null) return null;
    _editor.beats = [...b.beats];
    return _editor.selection;
  }

  bool get hasSelection => selection != null;

  void extend(int by) => _move((e) => e.extend(by));
  void extendString(int by) => _move((e) => e.extendString(by));

  /// Markierte Saiten (beide inklusive), null = alle.
  (int, int)? get stringSelection => _editor.stringSelection;
  void selectRange(int from, int to) => _move((e) => e.selectRange(from, to));
  void selectAll() => _move((e) => e.selectAll());
  void clearSelection() {
    markMode = false;
    _move((e) {
      e.anchor = null;
      e.stringAnchor = null;
    });
  }

  /// Markieren über das Zahlenfeld: Solange an, erweitern ← und → die
  /// Markierung (auf der Tastatur geht das mit Umschalt).
  bool markMode = false;

  void toggleMark() {
    markMode = !markMode;
    _move((e) {
      e.anchor = markMode && e.beats.isNotEmpty ? e.beat.clamp(0, e.beats.length - 1) : null;
      e.stringAnchor = null;
    });
  }

  /// Kopieren: die markierten Einträge (ohne Markierung der unter dem Cursor).
  List<TabBeat> copy() {
    final b = block;
    if (b == null) return const [];
    _editor.beats = [...b.beats];
    return _editor.copySelection();
  }

  void deleteSelection() {
    markMode = false;
    _edit((e) => e.deleteSelection());
  }

  void paste(List<TabBeat> clip) {
    markMode = false;
    _edit((e) => e.paste(clip));
  }

  void digit(int d) => _edit((e) {
    e.anchor = null;
    e.digit(d);
  });
  void setFret(int f) => _edit((e) => e.setFret(f));
  void setValue(int v) => _edit((e) => e.setValue(v));
  void bend(int quarters) => _edit((e) => e.bend(quarters));
  void slideIn(int dir) => _edit((e) => e.slideIn(dir));
  void slideOut(int dir) => _edit((e) => e.slideOut(dir));

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
        markMode ? extend(-1) : _move((e) => e.move(-1));
      case TabAction.right:
        markMode ? extend(1) : _move((e) => e.move(1));
      case TabAction.up:
        markMode ? extendString(-1) : _move((e) => e.moveString(-1));
      case TabAction.down:
        markMode ? extendString(1) : _move((e) => e.moveString(1));
      case TabAction.shorter:
        _edit((e) => e.shorter());
      case TabAction.longer:
        _edit((e) => e.shorter(-1));
      case TabAction.dot:
        _edit((e) => e.toggleDot());
      case TabAction.triplet:
        _edit((e) => e.toggleTriplet());
      case TabAction.rest:
        _edit((e) => e.rest());
      case TabAction.bar:
        _edit((e) => e.bar());
      case TabAction.slide:
        _edit((e) => e.toggleSlide());
      case TabAction.slideIn:
        _edit((e) => e.cycleSlideIn());
      case TabAction.slideOut:
        _edit((e) => e.cycleSlideOut());
      case TabAction.bend:
        _edit((e) => e.cycleBend());
      case TabAction.tie:
        _edit((e) => e.toggleTie());
      case TabAction.staccato:
        _edit((e) => e.toggleStaccato());
      case TabAction.accent:
        _edit((e) => e.toggleAccent());
      case TabAction.repeatStart:
        _edit((e) => e.repeatStart());
      case TabAction.repeatEnd:
        _edit((e) => e.repeatEnd());
      case TabAction.finalBar:
        _edit((e) => e.finalBar());
      case TabAction.doubleBar:
        _edit((e) => e.doubleBar());
      case TabAction.clearNote:
        _edit((e) => e.deleteSelection() ? null : e.clearNote());
      case TabAction.deleteBeat:
        _edit((e) => e.deleteSelection() ? null : e.deleteBeat());
      case TabAction.insertBeat:
        _edit((e) => e.insertBeat());
      case TabAction.insertMeasure:
        _edit((e) => e.insertMeasure());
      case TabAction.deleteMeasure:
        _edit((e) => e.deleteMeasure());
      case TabAction.finish:
        return false;
      default:
        break;
    }
    return true;
  }
}
