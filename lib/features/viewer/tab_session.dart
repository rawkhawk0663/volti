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
    final sel =
        _editor.selection ?? (_editor.beat.clamp(0, b.beats.length - 1), _editor.beat.clamp(0, b.beats.length - 1));
    if (sel.$2 - sel.$1 + 1 != beats.length) return TabClip(beats);
    final l = layoutTab(b, _unit);
    final g = l.gap;
    final left = l.xs[sel.$1] - l.slotWidths[sel.$1] / 2;
    final right = l.xs[sel.$2] + l.slotWidths[sel.$2] / 2;
    // Stelle jedes Eintrags, gemessen ab dem Taktstrich vor dem Kopierten
    // (bzw. dem Anfang der Zeile), in Linienabständen: So steht beim
    // Einfügen alles wieder genau gleich, auch in einer anderen Tabulatur.
    var ref = l.contentStart;
    for (var i = sel.$1 - 1; i >= 0; i--) {
      if (b.beats[i].bar) {
        ref = l.xs[i];
        break;
      }
    }
    return TabClip(
      beats,
      offsets: [for (var i = sel.$1; i <= sel.$2; i++) (l.xs[i] - ref) / g],
      // Von Hand angeordnet (Taktstriche oder Noten verschoben)?
      manual: b.beats.any((x) => x.at != null),
      width: (right - left) / g,
    );
  }

  void deleteSelection() {
    markMode = false;
    _edit((e) => e.deleteSelection());
  }

  /// Einfügen mit der Anordnung des Kopierten.
  ///
  /// Hatte die kopierte Tabulatur von Hand verschobene Taktstriche oder
  /// Noten, steht danach jeder eingefügte Taktstrich im gleichen Abstand zum
  /// vorigen wie beim Kopieren (also jeder Takt gleich breit, die Noten darin
  /// an der gleichen Stelle). Der Taktstrich vor der Einfügestelle wird
  /// festgehalten, damit davor nichts verrutscht; verschobene Taktstriche
  /// dahinter rücken um die eingefügte Breite nach rechts. Reicht der Platz
  /// nicht, wird die Zeile breiter (so weit die Seite reicht), die
  /// bestehenden Takte bleiben dabei, wo sie sind; erst danach wird das
  /// Eingefügte gleichmässig zusammengeschoben.
  void paste(TabClip clip) {
    markMode = false;
    final b = block;
    if (b == null || clip.beats.isEmpty) return;
    final e = _editor;
    e.beats = [...b.beats];
    e.beat = e.beat.clamp(0, b.beats.length);
    e.measure = b.measure;
    e.meter = b.meter;

    // Wird eine Markierung ersetzt: ihre Breite vor dem Löschen.
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
    final g = l.gap, start = l.contentStart, n = e.beats.length;

    // Feste Stellen (in Bildpunkten) der bestehenden Taktstriche: verschobene
    // bleiben, die hinter der Einfügestelle rücken um die eingefügte Breite.
    final shiftPx = clip.width * g - replacedWidth;
    final fixed = <int, double>{};
    for (var i = 0; i < n; i++) {
      if (e.beats[i].bar && e.beats[i].at != null) fixed[i] = i >= at ? l.xs[i] + shiftPx : l.xs[i];
    }
    var prevIdx = -1;
    for (var i = math.min(at, n) - 1; i >= 0; i--) {
      if (e.beats[i].bar) {
        prevIdx = i;
        break;
      }
    }
    final prevX = prevIdx >= 0 ? l.xs[prevIdx] : start;
    // Stellen aller eingefügten Einträge: wie beim Kopieren, ab dem
    // Taktstrich vor der Einfügestelle.
    final pasted = <int, double>{};
    if (clip.manual) {
      if (prevIdx >= 0) fixed[prevIdx] = prevX; // davor nichts verrutschen
      for (var k = 0; k < clip.beats.length; k++) {
        final off = clip.offsetOf(k);
        if (off != null) pasted[k] = prevX + off * g;
      }
    }

    // Platz: nötigenfalls die Zeile breiter machen (bestehende Stellen
    // bleiben, weil sie hier in Bildpunkten stehen).
    var widthPx = l.width;
    var span = l.contentEnd - start;
    final room = g * 2.6; // Platz hinter dem Letzten (wie am Zeilenende üblich)
    final furthest = [...fixed.values, ...pasted.values].fold<double>(start, math.max);
    if (furthest + room > l.contentEnd) {
      final maxWidth = (1.0 - b.x - 0.01) * _unit.width;
      final grow = math.min(furthest + room - l.contentEnd, maxWidth - widthPx);
      if (grow > 0) {
        widthPx += grow;
        span += grow;
      }
    }
    // Reicht es immer noch nicht: das Eingefügte und alles dahinter
    // gleichmässig zusammenschieben.
    final end = start + span - room;
    if (furthest > end && furthest > prevX) {
      final k = math.max(0.1, (end - prevX) / (furthest - prevX));
      pasted.updateAll((_, x) => prevX + (x - prevX) * k);
      for (final i in fixed.keys.toList()) {
        if (i >= at) fixed[i] = prevX + (fixed[i]! - prevX) * k;
      }
    }
    double frac(double x) => ((x - start) / span).clamp(0.0, 1.0);

    for (final f in fixed.entries) {
      e.beats[f.key] = e.beats[f.key].withAt(frac(f.value));
    }
    final items = [
      for (final (k, x) in clip.beats.indexed) x.bar && pasted[k] != null ? x.withAt(frac(pasted[k]!)) : x.withoutAt,
    ];
    e.insertPasted(at, items);
    // Noten: Mit den nun festen Taktstrichen ihre Lage im Takt so setzen,
    // dass sie genau dort stehen wie beim Kopieren.
    if (pasted.isNotEmpty) {
      final t2 = b.copyWith(beats: e.beats, width: widthPx / _unit.width);
      final l2 = layoutTab(t2, _unit);
      for (final p in pasted.entries) {
        final i = at + p.key;
        if (e.beats[i].bar) continue;
        final (lo, hi) = measureSpanOf(t2, l2, i);
        e.beats[i] = e.beats[i].withAt(((p.value - lo) / (hi - lo)).clamp(0.0, 1.0));
      }
    }
    ink.updateTab(id, beats: e.beats, width: widthPx != l.width ? widthPx / _unit.width : null);
    notifyListeners();
  }

  void digit(int d) => _edit((e) {
    e.anchor = null;
    e.digit(d);
  });
  void setFret(int f) => _edit((e) => e.setFret(f));
  void setValue(int v) => _edit((e) => e.setValue(v));
  void setDots(int n) => _edit((e) => e.setDots(n));

  /// Farbige Markierung für das Markierte (bzw. den Schlag unter dem Cursor).
  void setHighlight(int argb) => _edit((e) => e.setHighlight(argb));

  /// Farbe der Markierung im Markierten (bzw. unter dem Cursor), 0 = keine.
  int get currentHighlight {
    final b = block;
    if (b == null || b.beats.isEmpty) return 0;
    _editor.beats = [...b.beats];
    final sel = _editor.selection ?? (beat, beat);
    for (var i = sel.$1; i <= sel.$2 && i < b.beats.length; i++) {
      if (!b.beats[i].bar) return b.beats[i].highlight;
    }
    return 0;
  }

  void bend(int quarters) => _edit((e) => e.bend(quarters));

  /// Zeichen für das Markierte bzw. den Schlag unter dem Cursor setzen
  /// (gleicher Wert nochmals = entfernen).
  void setMark(TabMark m, int value) => _edit((e) => e.setMark(m, value));
  void setHarmonic(int kind) => _edit((e) => e.setHarmonic(kind));

  /// Wert eines Zeichens im Markierten bzw. unter dem Cursor (0 = keines).
  int currentMark(TabMark m) {
    final b = block;
    if (b == null) return 0;
    _editor.beats = [...b.beats];
    return _editor.currentMark(m);
  }

  /// Gibt die Note unter dem Cursor gerade einen Trillerbund ein?
  bool get trillInput => _editor.trillInput;
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
      case TabAction.ghostParen:
        _edit((e) => e.toggleGhostParen());
      case TabAction.trill:
        _edit((e) => e.toggleTrill());
      case TabAction.harmonic:
        _edit((e) => e.cycleHarmonic());
      case TabAction.letRing:
        _edit((e) => e.cycleMark(TabMark.letRing));
      case TabAction.vibrato:
        _edit((e) => e.cycleMark(TabMark.vibrato));
      case TabAction.whammy:
        _edit((e) => e.cycleMark(TabMark.whammy));
      case TabAction.tapSlapPop:
        _edit((e) => e.cycleMark(TabMark.tap));
      case TabAction.tremolo:
        _edit((e) => e.cycleMark(TabMark.tremolo));
      case TabAction.fermata:
        _edit((e) => e.cycleMark(TabMark.fermata));
      case TabAction.pick:
        _edit((e) => e.cycleMark(TabMark.pick));
      case TabAction.strum:
        _edit((e) => e.cycleMark(TabMark.strum));
      case TabAction.rake:
        _edit((e) => e.cycleMark(TabMark.rake));
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
  const TabClip(this.beats, {this.offsets = const [], this.manual = false, this.width = 0});

  final List<TabBeat> beats;

  /// Pro Eintrag seine Stelle ab dem Taktstrich vor dem Kopierten (bzw. dem
  /// Anfang der Zeile), in Linienabständen.
  final List<double> offsets;

  /// War die Tabulatur von Hand angeordnet? Dann werden beim Einfügen alle
  /// Taktstriche genau gesetzt.
  final bool manual;

  /// Breite des Kopierten (in Linienabständen).
  final double width;

  bool get isEmpty => beats.isEmpty;
  bool get isNotEmpty => beats.isNotEmpty;

  double? offsetOf(int i) => i < offsets.length ? offsets[i] : null;
}
