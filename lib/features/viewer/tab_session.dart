import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import '../../core/ink/tab_block.dart';
import 'ink_controller.dart';
import 'tab_paint.dart';
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

  /// Wartet die nächste Bundzahl darauf, Vorschlagsnote zu werden?
  bool get graceInput => _editor.graceInput;

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
    _editor.meter = b.meter;
    op(_editor);
    final m = _editor.meter;
    ink.updateTab(id, beats: _editor.beats, meter: m, clearMeter: m == null);
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
  void selectColumn() => _move((e) => e.selectColumn());

  /// Taktart im Takt mit dem Cursor (null = frei).
  String? get measureMeter {
    final b = block;
    if (b == null) return null;
    return meterOfMeasure(b.beats, b.meter, _measureIndex(b));
  }

  /// Nummer des Takts mit dem Cursor.
  int get measureNumber {
    final b = block;
    return b == null ? 0 : _measureIndex(b);
  }

  int _measureIndex(TabBlock b) =>
      (TabEditor(b.beats, meter: b.meter)..beat = _editor.beat.clamp(0, b.beats.length)).measureIndex;

  /// Taktart nur für diesen Takt ändern.
  void setMeasureMeter(String m) => _edit((e) => e.setMeasureMeter(m));

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

  /// Grösse, mit der die Anordnung berechnet wird. Waagrecht hängt alles nur
  /// von der Breite ab (Lagen sind Anteile), die Zahl selbst ist beliebig.
  static const _unit = Size(1000, 1000);

  /// Kopieren: die markierten Einträge (ohne Markierung der unter dem Cursor),
  /// dazu die Anordnung, damit die Takte beim Einfügen gleich breit sind.
  TabClip copy() {
    final b = block;
    if (b == null) return const TabClip([]);
    _editor.beats = [...b.beats];
    final beats = _editor.copySelection();
    if (beats.isEmpty || b.beats.isEmpty) return TabClip(beats);
    final sel = _editor.selection ?? (_editor.beat.clamp(0, b.beats.length - 1), _editor.beat.clamp(0, b.beats.length - 1));
    if (sel.$2 - sel.$1 + 1 != beats.length) return TabClip(beats);
    final l = layoutTab(b, _unit);
    final g = l.gap;
    final left = l.xs[sel.$1] - l.slotWidths[sel.$1] / 2;
    final right = l.xs[sel.$2] + l.slotWidths[sel.$2] / 2;
    // Abstand jedes Taktstrichs zum Taktstrich davor (bzw. zum Anfang der
    // Zeile), in Linienabständen: So wird jeder Takt beim Einfügen gleich
    // breit, auch in einer anderen Tabulatur.
    var prev = l.contentStart;
    for (var i = sel.$1 - 1; i >= 0; i--) {
      if (b.beats[i].bar) {
        prev = l.xs[i];
        break;
      }
    }
    final steps = <double?>[];
    for (var i = sel.$1; i <= sel.$2; i++) {
      if (b.beats[i].bar) {
        steps.add((l.xs[i] - prev) / g);
        prev = l.xs[i];
      } else {
        steps.add(null);
      }
    }
    return TabClip(
      beats,
      barSteps: steps,
      anchored: [for (var i = sel.$1; i <= sel.$2; i++) b.beats[i].at != null],
      width: (right - left) / g,
    );
  }

  void deleteSelection() {
    markMode = false;
    _edit((e) => e.deleteSelection());
  }

  /// Einfügen mit der Anordnung des Kopierten: Von Hand verschobene
  /// Taktstriche stehen im gleichen Abstand wie beim Kopieren, von Hand
  /// verschobene Noten behalten ihre Lage im Takt. Verschobene Taktstriche
  /// dahinter rücken um die eingefügte Breite nach rechts.
  void paste(TabClip clip) {
    markMode = false;
    if (clip.beats.isEmpty) return;
    _edit((e) {
      final b = block!;
      // Wird eine Markierung ersetzt: ihre Stelle und Breite vor dem Löschen.
      final ss = e.stringSelection;
      final replaced = ss == null || (ss.$1 == 0 && ss.$2 == TabBlock.strings - 1) ? e.selection : null;
      var replacedWidth = 0.0;
      if (replaced != null) {
        final before = layoutTab(b.copyWith(beats: e.beats), _unit);
        replacedWidth =
            before.xs[replaced.$2] +
            before.slotWidths[replaced.$2] / 2 -
            (before.xs[replaced.$1] - before.slotWidths[replaced.$1] / 2);
      }
      final at = e.preparePaste();
      final l = layoutTab(b.copyWith(beats: e.beats), _unit);
      final g = l.gap, span = l.contentEnd - l.contentStart;
      final n = e.beats.length;
      double frac(double x) => ((x - l.contentStart) / span).clamp(0.0, 1.0);
      final shift = (clip.width * g - replacedWidth) / span;
      for (var i = at; i < n; i++) {
        final x = e.beats[i];
        if (x.bar && x.at != null) e.beats[i] = x.withAt((x.at! + shift).clamp(0.0, 1.0));
      }
      // Taktstrich vor der Einfügestelle (bzw. Anfang der Zeile): von dort
      // aus bekommt jeder eingefügte Takt seine Breite.
      var prevX = l.contentStart;
      for (var i = math.min(at, n) - 1; i >= 0; i--) {
        if (e.beats[i].bar) {
          prevX = l.xs[i];
          break;
        }
      }
      final items = <TabBeat>[];
      for (final (k, x) in clip.beats.indexed) {
        final step = clip.stepOf(k);
        if (!x.bar || step == null) {
          items.add(x.bar ? x.withoutAt : x);
          continue;
        }
        prevX += step * g;
        items.add(clip.isAnchored(k) ? x.withAt(frac(prevX)) : x.withoutAt);
      }
      e.insertPasted(at, items);
    });
  }

  void digit(int d) => _edit((e) {
    e.anchor = null;
    e.digit(d);
  });
  void setFret(int f) => _edit((e) => e.setFret(f));
  void setValue(int v) => _edit((e) => e.setValue(v));
  void setDots(int n) => _edit((e) => e.setDots(n));
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
        markMode ? selectColumn() : _move((e) => e.moveString(-1));
      case TabAction.down:
        markMode ? selectColumn() : _move((e) => e.moveString(1));
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
      case TabAction.tieIn:
        _edit((e) => e.toggleTieIn());
      case TabAction.legato:
        _edit((e) => e.toggleLegato());
      case TabAction.grace:
        _edit((e) => e.toggleGrace());
      case TabAction.transposeUp:
        _edit((e) => e.transpose(1));
      case TabAction.transposeDown:
        _edit((e) => e.transpose(-1));
      case TabAction.staccato:
        _edit((e) => e.toggleStaccato());
      case TabAction.accent:
        _edit((e) => e.toggleAccent());
      case TabAction.palmMute:
        _edit((e) => e.togglePalmMute());
      case TabAction.ghost:
        _edit((e) => e.toggleGhost());
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

/// Kopierte Schläge einer Tabulatur mit ihrer Anordnung.
class TabClip {
  const TabClip(this.beats, {this.barSteps = const [], this.anchored = const [], this.width = 0});

  final List<TabBeat> beats;

  /// Pro Eintrag: bei einem Taktstrich sein Abstand zum Taktstrich davor
  /// (in Linienabständen), sonst null.
  final List<double?> barSteps;

  /// Pro Eintrag: war der Taktstrich von Hand verschoben?
  final List<bool> anchored;

  /// Breite des Kopierten (in Linienabständen).
  final double width;

  bool get isEmpty => beats.isEmpty;
  bool get isNotEmpty => beats.isNotEmpty;

  double? stepOf(int i) => i < barSteps.length ? barSteps[i] : null;
  bool isAnchored(int i) => i < anchored.length && anchored[i];
}
