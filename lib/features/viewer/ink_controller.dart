import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/ink/score_annotations.dart';
import '../../core/ink/selection.dart';
import '../../core/ink/stamp.dart';
import '../../core/ink/stroke.dart';
import '../../core/ink/text_note.dart';
import '../../core/library/sidecar_store.dart';

/// Eine rückgängig machbare Aktion: was dazukam, was entfernt und was
/// geändert wurde.
class _UndoEntry {
  _UndoEntry({
    List<String>? added,
    List<Stroke>? removed,
    List<String>? addedTexts,
    List<TextNote>? removedTexts,
    List<TextNote>? textsBefore,
    List<String>? addedStamps,
    List<Stamp>? removedStamps,
    List<Stamp>? stampsBefore,
    List<Stroke>? strokesBefore,
  }) : added = added ?? [],
       removed = removed ?? [],
       addedTexts = addedTexts ?? [],
       removedTexts = removedTexts ?? [],
       textsBefore = textsBefore ?? [],
       addedStamps = addedStamps ?? [],
       removedStamps = removedStamps ?? [],
       stampsBefore = stampsBefore ?? [],
       strokesBefore = strokesBefore ?? [];

  final List<String> added;
  final List<Stroke> removed;
  final List<String> addedTexts;
  final List<TextNote> removedTexts;

  /// Text-Notizen vor einer Änderung (Text bearbeitet oder verschoben).
  final List<TextNote> textsBefore;

  final List<String> addedStamps;
  final List<Stamp> removedStamps;

  /// Stempel vor dem Verschieben.
  final List<Stamp> stampsBefore;

  /// Striche vor einer Änderung (verschoben, vergrössert, umgefärbt).
  final List<Stroke> strokesBefore;

  bool get isEmpty =>
      added.isEmpty &&
      removed.isEmpty &&
      addedTexts.isEmpty &&
      removedTexts.isEmpty &&
      textsBefore.isEmpty &&
      addedStamps.isEmpty &&
      removedStamps.isEmpty &&
      stampsBefore.isEmpty &&
      strokesBefore.isEmpty;
}

/// Verwaltet die Anmerkungen eines Stücks: Zeichnen, Radieren,
/// Rückgängig/Wiederholen und automatisches Speichern.
class InkController extends ChangeNotifier {
  InkController({required this.pdfPath, SidecarStore? store}) : _store = store ?? const SidecarStore();

  final String pdfPath;
  final SidecarStore _store;
  static const _uuid = Uuid();

  ScoreAnnotations _annotations = ScoreAnnotations();
  ScoreAnnotations get annotations => _annotations;

  final List<_UndoEntry> _undo = [];
  final List<_UndoEntry> _redo = [];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  Timer? _saveTimer;
  bool _dirty = false;

  /// Zuletzt beim Speichern aufgetretener Fehler (für die Anzeige).
  String? saveError;

  Future<void> load() async {
    _annotations = (await _store.load(pdfPath)).annotations;
    notifyListeners();
  }

  /// Fügt einen fertig gezeichneten Strich hinzu.
  void addStroke({
    required int page,
    required InkTool tool,
    required int color,
    required double width,
    required List<InkPoint> points,
  }) {
    if (points.isEmpty) return;
    final stroke = Stroke(
      id: _uuid.v4(),
      page: page,
      tool: tool,
      color: color,
      width: width,
      points: List.unmodifiable(points),
      createdAt: DateTime.now().toUtc(),
    );
    _annotations.put(stroke);
    _push(_UndoEntry(added: [stroke.id]));
  }

  /// Löscht die angegebenen Striche (Radierer).
  void eraseStrokes(Iterable<Stroke> strokes) {
    final now = DateTime.now().toUtc();
    final removed = <Stroke>[];
    for (final s in strokes) {
      if (s.deleted) continue;
      _annotations.put(s.markDeleted(now));
      removed.add(s);
    }
    if (removed.isEmpty) return;
    _push(_UndoEntry(removed: removed));
  }

  /// Teilweise radieren: [original] wird durch die übrig gebliebenen Stücke
  /// ersetzt (neue Striche mit neuen IDs, das Original wird zum Grabstein).
  void replaceStroke(Stroke original, List<List<InkPoint>> pieces) {
    if (original.deleted) return;
    final now = DateTime.now().toUtc();
    _annotations.put(original.markDeleted(now));
    final ids = <String>[];
    for (final piece in pieces) {
      final s = Stroke(
        id: _uuid.v4(),
        page: original.page,
        tool: original.tool,
        color: original.color,
        width: original.width,
        points: List.unmodifiable(piece),
        createdAt: original.createdAt,
        modifiedAt: now,
      );
      _annotations.put(s);
      ids.add(s.id);
    }
    _push(_UndoEntry(added: ids, removed: [original]));
  }

  // ---------------------------------------------- mehrere Schritte bündeln
  _UndoEntry? _batch;

  /// Alles bis [endBatch] wird ein einziger Schritt für "Rückgängig"
  /// (z. B. ein ganzer Radier-Zug).
  void beginBatch() => _batch ??= _UndoEntry();

  void endBatch() {
    final b = _batch;
    _batch = null;
    if (b == null) return;
    if (b.isEmpty) {
      return;
    }
    _undo.add(b);
    if (_undo.length > 200) _undo.removeAt(0);
    _redo.clear();
    notifyListeners();
  }

  // ------------------------------------------------------------ Text-Notizen

  /// Neue Text-Notiz. Gibt ihre ID zurück (null bei leerem Text).
  /// [size] ist relativ zur Seitenbreite.
  String? addText({
    required int page,
    required double x,
    required double y,
    required String text,
    required double size,
    required int color,
    int background = TextNote.legacyBackground,
    TextFont font = TextFont.sans,
    bool bold = false,
    bool italic = false,
  }) {
    if (text.trim().isEmpty) return null;
    final note = TextNote(
      id: _uuid.v4(),
      page: page,
      x: x,
      y: y,
      text: text.trimRight(),
      size: size,
      color: color,
      background: background,
      font: font,
      bold: bold,
      italic: italic,
      createdAt: DateTime.now().toUtc(),
    );
    _annotations.putText(note);
    _push(_UndoEntry(addedTexts: [note.id]));
    return note.id;
  }

  /// Text, Stil und/oder Position ändern. Leerer Text löscht die Notiz.
  void updateText(
    String id, {
    String? text,
    double? x,
    double? y,
    double? size,
    int? color,
    int? background,
    TextFont? font,
    bool? bold,
    bool? italic,
  }) {
    final before = _annotations.text(id);
    if (before == null || before.deleted) return;
    if (text != null && text.trim().isEmpty) {
      deleteTexts([before]);
      return;
    }
    final after = before.copyWith(
      text: text?.trimRight(),
      x: x,
      y: y,
      size: size,
      color: color,
      background: background,
      font: font,
      bold: bold,
      italic: italic,
      modifiedAt: DateTime.now().toUtc(),
    );
    if (after.text == before.text &&
        after.x == before.x &&
        after.y == before.y &&
        after.size == before.size &&
        after.color == before.color &&
        after.background == before.background &&
        after.font == before.font &&
        after.bold == before.bold &&
        after.italic == before.italic) {
      return;
    }
    _annotations.putText(after);
    _push(_UndoEntry(textsBefore: [before]));
  }

  void deleteTexts(Iterable<TextNote> notes) {
    final now = DateTime.now().toUtc();
    final removed = <TextNote>[];
    for (final t in notes) {
      if (t.deleted) continue;
      _annotations.putText(t.copyWith(deleted: true, modifiedAt: now));
      removed.add(t);
    }
    if (removed.isEmpty) return;
    _push(_UndoEntry(removedTexts: removed));
  }

  /// Entfernt alle Striche und Text-Notizen einer Seite (rückgängig machbar).
  void clearPage(int page) {
    final now = DateTime.now().toUtc();
    final strokes = _annotations.visibleStrokesOn(page);
    final texts = _annotations.visibleTextsOn(page);
    final stamps = _annotations.visibleStampsOn(page);
    if (strokes.isEmpty && texts.isEmpty && stamps.isEmpty) return;
    for (final st in stamps) {
      _annotations.putStamp(st.copyWith(deleted: true, modifiedAt: now));
    }
    for (final s in strokes) {
      _annotations.put(s.markDeleted(now));
    }
    for (final t in texts) {
      _annotations.putText(t.copyWith(deleted: true, modifiedAt: now));
    }
    _push(_UndoEntry(removed: strokes, removedTexts: texts, removedStamps: stamps));
  }

  bool pageHasAnnotations(int page) =>
      _annotations.visibleStrokesOn(page).isNotEmpty ||
      _annotations.visibleTextsOn(page).isNotEmpty ||
      _annotations.visibleStampsOn(page).isNotEmpty;

  // ---------------------------------------------------------------- Stempel
  String addStamp({
    required int page,
    required double x,
    required double y,
    required int glyph,
    required double size,
    required int color,
  }) {
    final st = Stamp(
      id: _uuid.v4(),
      page: page,
      x: x,
      y: y,
      glyph: glyph,
      size: size,
      color: color,
      createdAt: DateTime.now().toUtc(),
    );
    _annotations.putStamp(st);
    _push(_UndoEntry(addedStamps: [st.id]));
    return st.id;
  }

  void moveStamp(String id, double x, double y) {
    final before = _annotations.stamp(id);
    if (before == null || before.deleted || (before.x == x && before.y == y)) return;
    _annotations.putStamp(before.copyWith(x: x, y: y, modifiedAt: DateTime.now().toUtc()));
    _push(_UndoEntry(stampsBefore: [before]));
  }

  void deleteStamps(Iterable<Stamp> stamps) {
    final now = DateTime.now().toUtc();
    final removed = <Stamp>[];
    for (final st in stamps) {
      if (st.deleted) continue;
      _annotations.putStamp(st.copyWith(deleted: true, modifiedAt: now));
      removed.add(st);
    }
    if (removed.isEmpty) return;
    _push(_UndoEntry(removedStamps: removed));
  }

  // ------------------------------------------------------- Auswahl (Lasso)

  /// Verschiebt und/oder vergrössert die Auswahl – ein Rückgängig-Schritt.
  void transformSelection(SelectionIds ids, SelectionTransform tf) {
    if (tf.isIdentity) return;
    final now = DateTime.now().toUtc();
    final entry = _UndoEntry();
    for (final id in ids.strokes) {
      final s = _annotations[id];
      if (s == null || s.deleted) continue;
      _annotations.put(
        s.copyWith(
          points: List.unmodifiable([
            for (final p in s.points)
              () {
                final q = tf.apply(Offset(p.x, p.y));
                return InkPoint(q.dx, q.dy, p.pressure);
              }(),
          ]),
          width: s.width * tf.scale,
          modifiedAt: now,
        ),
      );
      entry.strokesBefore.add(s);
    }
    for (final id in ids.stamps) {
      final st = _annotations.stamp(id);
      if (st == null || st.deleted) continue;
      final q = tf.apply(Offset(st.x, st.y));
      _annotations.putStamp(st.copyWith(x: q.dx, y: q.dy, size: st.size * tf.scale, modifiedAt: now));
      entry.stampsBefore.add(st);
    }
    for (final id in ids.texts) {
      final n = _annotations.text(id);
      if (n == null || n.deleted) continue;
      final q = tf.apply(Offset(n.x, n.y));
      _annotations.putText(n.copyWith(x: q.dx, y: q.dy, size: n.size * tf.scale, modifiedAt: now));
      entry.textsBefore.add(n);
    }
    if (!entry.isEmpty) _push(entry);
  }

  /// Färbt die Auswahl um. Die Deckkraft (z. B. vom Textmarker) bleibt.
  void recolorSelection(SelectionIds ids, int color) {
    final now = DateTime.now().toUtc();
    final entry = _UndoEntry();
    for (final id in ids.strokes) {
      final s = _annotations[id];
      if (s == null || s.deleted) continue;
      final c = recolorKeepingAlpha(s.color, color);
      if (c == s.color) continue;
      _annotations.put(s.copyWith(color: c, modifiedAt: now));
      entry.strokesBefore.add(s);
    }
    for (final id in ids.stamps) {
      final st = _annotations.stamp(id);
      if (st == null || st.deleted) continue;
      final c = recolorKeepingAlpha(st.color, color);
      if (c == st.color) continue;
      _annotations.putStamp(st.copyWith(color: c, modifiedAt: now));
      entry.stampsBefore.add(st);
    }
    for (final id in ids.texts) {
      final n = _annotations.text(id);
      if (n == null || n.deleted) continue;
      final c = recolorKeepingAlpha(n.color, color);
      if (c == n.color) continue;
      _annotations.putText(n.copyWith(color: c, modifiedAt: now));
      entry.textsBefore.add(n);
    }
    if (!entry.isEmpty) _push(entry);
  }

  /// Löscht die Auswahl – ein Rückgängig-Schritt.
  void deleteSelection(SelectionIds ids) {
    final a = _annotations;
    beginBatch();
    eraseStrokes([for (final id in ids.strokes) ?a[id]]);
    deleteStamps([for (final id in ids.stamps) ?a.stamp(id)]);
    deleteTexts([for (final id in ids.texts) ?a.text(id)]);
    endBatch();
  }

  /// Kopie der Auswahl für die Zwischenablage.
  InkClip copySelection(SelectionIds ids) {
    final a = _annotations;
    return InkClip(
      strokes: [
        for (final id in ids.strokes)
          if (a[id] case final s? when !s.deleted) s,
      ],
      stamps: [
        for (final id in ids.stamps)
          if (a.stamp(id) case final s? when !s.deleted) s,
      ],
      texts: [
        for (final id in ids.texts)
          if (a.text(id) case final t? when !t.deleted) t,
      ],
    );
  }

  /// Fügt [clip] auf [page] ein, um [offset] verschoben (normiert).
  /// Alles bekommt neue IDs und liegt obenauf. Gibt die neue Auswahl zurück.
  SelectionIds paste(InkClip clip, int page, {Offset offset = Offset.zero}) {
    final now = DateTime.now().toUtc();
    final tf = SelectionTransform(delta: offset);
    final strokes = <String>{}, stamps = <String>{}, texts = <String>{};
    final entry = _UndoEntry();
    for (final s in clip.strokes) {
      final copy = Stroke(
        id: _uuid.v4(),
        page: page,
        tool: s.tool,
        color: s.color,
        width: s.width,
        createdAt: now,
        points: List.unmodifiable([
          for (final p in s.points)
            () {
              final q = tf.apply(Offset(p.x, p.y));
              return InkPoint(q.dx, q.dy, p.pressure);
            }(),
        ]),
      );
      _annotations.put(copy);
      strokes.add(copy.id);
      entry.added.add(copy.id);
    }
    for (final st in clip.stamps) {
      final q = tf.apply(Offset(st.x, st.y));
      final copy = Stamp(
        id: _uuid.v4(),
        page: page,
        x: q.dx,
        y: q.dy,
        glyph: st.glyph,
        size: st.size,
        color: st.color,
        createdAt: now,
      );
      _annotations.putStamp(copy);
      stamps.add(copy.id);
      entry.addedStamps.add(copy.id);
    }
    for (final n in clip.texts) {
      final q = tf.apply(Offset(n.x, n.y));
      final copy = TextNote(
        id: _uuid.v4(),
        page: page,
        x: q.dx,
        y: q.dy,
        text: n.text,
        size: n.size,
        color: n.color,
        background: n.background,
        font: n.font,
        bold: n.bold,
        italic: n.italic,
        createdAt: now,
      );
      _annotations.putText(copy);
      texts.add(copy.id);
      entry.addedTexts.add(copy.id);
    }
    if (!entry.isEmpty) _push(entry);
    return SelectionIds(strokes: strokes, stamps: stamps, texts: texts);
  }

  // ------------------------------------------------- Rückgängig/Wiederholen

  void undo() => _apply(_undo, _redo);
  void redo() => _apply(_redo, _undo);

  /// Kehrt eine Aktion um. Gelöschtes kommt als *Kopie mit neuer ID*
  /// zurück – so bleibt das Zusammenführen beim Sync eindeutig
  /// ("gelöscht bleibt gelöscht").
  void _apply(List<_UndoEntry> from, List<_UndoEntry> to) {
    if (from.isEmpty) return;
    final entry = from.removeLast();
    final now = DateTime.now().toUtc();
    final inverse = _UndoEntry();

    for (final id in entry.added) {
      final s = _annotations[id];
      if (s != null && !s.deleted) {
        _annotations.put(s.markDeleted(now));
        inverse.removed.add(s);
      }
    }
    for (final s in entry.removed) {
      final copy = Stroke(
        id: _uuid.v4(),
        page: s.page,
        tool: s.tool,
        color: s.color,
        width: s.width,
        points: s.points,
        createdAt: s.createdAt,
        modifiedAt: now,
      );
      _annotations.put(copy);
      inverse.added.add(copy.id);
      _renameInHistory(s.id, copy.id);
    }
    for (final id in entry.addedTexts) {
      final t = _annotations.text(id);
      if (t != null && !t.deleted) {
        _annotations.putText(t.copyWith(deleted: true, modifiedAt: now));
        inverse.removedTexts.add(t);
      }
    }
    for (final t in entry.removedTexts) {
      final copy = t.copyWith(id: _uuid.v4(), modifiedAt: now, deleted: false);
      _annotations.putText(copy);
      inverse.addedTexts.add(copy.id);
      _renameInHistory(t.id, copy.id);
    }
    for (final before in entry.textsBefore) {
      final current = _annotations.text(before.id);
      if (current == null || current.deleted) continue;
      _annotations.putText(before.copyWith(modifiedAt: now));
      inverse.textsBefore.add(current);
    }
    for (final id in entry.addedStamps) {
      final st = _annotations.stamp(id);
      if (st != null && !st.deleted) {
        _annotations.putStamp(st.copyWith(deleted: true, modifiedAt: now));
        inverse.removedStamps.add(st);
      }
    }
    for (final st in entry.removedStamps) {
      final copy = st.copyWith(id: _uuid.v4(), modifiedAt: now, deleted: false);
      _annotations.putStamp(copy);
      inverse.addedStamps.add(copy.id);
      _renameInHistory(st.id, copy.id);
    }
    for (final before in entry.stampsBefore) {
      final current = _annotations.stamp(before.id);
      if (current == null || current.deleted) continue;
      _annotations.putStamp(before.copyWith(modifiedAt: now));
      inverse.stampsBefore.add(current);
    }
    for (final before in entry.strokesBefore) {
      final current = _annotations[before.id];
      if (current == null || current.deleted) continue;
      _annotations.put(before.copyWith(modifiedAt: now));
      inverse.strokesBefore.add(current);
    }
    to.add(inverse);
    _changed();
  }

  /// Ältere Einträge im Verlauf zeigen auf die alte ID – auf die Kopie umbiegen,
  /// damit z. B. "Zeichnen rückgängig" danach den wiederhergestellten Strich trifft.
  void _renameInHistory(String oldId, String newId) {
    for (final e in [..._undo, ..._redo]) {
      for (final list in [e.added, e.addedTexts, e.addedStamps]) {
        final i = list.indexOf(oldId);
        if (i >= 0) list[i] = newId;
      }
      for (var i = 0; i < e.textsBefore.length; i++) {
        if (e.textsBefore[i].id == oldId) e.textsBefore[i] = e.textsBefore[i].copyWith(id: newId);
      }
      for (var i = 0; i < e.stampsBefore.length; i++) {
        if (e.stampsBefore[i].id == oldId) e.stampsBefore[i] = e.stampsBefore[i].copyWith(id: newId);
      }
      for (var i = 0; i < e.strokesBefore.length; i++) {
        if (e.strokesBefore[i].id == oldId) e.strokesBefore[i] = e.strokesBefore[i].copyWith(id: newId);
      }
    }
  }

  void _push(_UndoEntry e) {
    final b = _batch;
    if (b != null) {
      // Innerhalb eines Bündels: Was im selben Bündel erst entstanden ist und
      // gleich wieder entfernt wird, taucht im Verlauf gar nicht auf.
      for (final r in e.removed) {
        if (!b.added.remove(r.id)) b.removed.add(r);
      }
      b.added.addAll(e.added);
      for (final r in e.removedTexts) {
        if (!b.addedTexts.remove(r.id)) b.removedTexts.add(r);
      }
      b.addedTexts.addAll(e.addedTexts);
      b.textsBefore.addAll(e.textsBefore);
      for (final r in e.removedStamps) {
        if (!b.addedStamps.remove(r.id)) b.removedStamps.add(r);
      }
      b.addedStamps.addAll(e.addedStamps);
      b.stampsBefore.addAll(e.stampsBefore);
      b.strokesBefore.addAll(e.strokesBefore);
      _changed();
      return;
    }
    _undo.add(e);
    if (_undo.length > 200) _undo.removeAt(0);
    _redo.clear();
    _changed();
  }

  void _changed() {
    _dirty = true;
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), save);
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    if (!_dirty) return;
    _dirty = false;
    try {
      final merged = (await _store.save(pdfPath, annotations: _annotations)).annotations;
      // Falls ein anderes Gerät inzwischen etwas ergänzt hat, übernehmen.
      _annotations = ScoreAnnotations.merge(_annotations, merged);
      saveError = null;
    } catch (e) {
      _dirty = true;
      saveError = 'Speichern fehlgeschlagen: $e';
    }
    if (!_disposed) notifyListeners();
  }

  bool _disposed = false;
  bool get isDisposed => _disposed;

  /// Beim Schliessen werden ungespeicherte Änderungen noch geschrieben.
  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    if (_dirty) unawaited(save());
    super.dispose();
  }
}
