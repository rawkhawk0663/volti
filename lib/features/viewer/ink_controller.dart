import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/ink/score_annotations.dart';
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
  }) : added = added ?? [],
       removed = removed ?? [],
       addedTexts = addedTexts ?? [],
       removedTexts = removedTexts ?? [],
       textsBefore = textsBefore ?? [];

  final List<String> added;
  final List<Stroke> removed;
  final List<String> addedTexts;
  final List<TextNote> removedTexts;

  /// Text-Notizen vor einer Änderung (Text bearbeitet oder verschoben).
  final List<TextNote> textsBefore;
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
      createdAt: DateTime.now().toUtc(),
    );
    _annotations.putText(note);
    _push(_UndoEntry(addedTexts: [note.id]));
    return note.id;
  }

  /// Text, Stil und/oder Position ändern. Leerer Text löscht die Notiz.
  void updateText(String id, {String? text, double? x, double? y, double? size, int? color, int? background}) {
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
      modifiedAt: DateTime.now().toUtc(),
    );
    if (after.text == before.text &&
        after.x == before.x &&
        after.y == before.y &&
        after.size == before.size &&
        after.color == before.color &&
        after.background == before.background) {
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
    if (strokes.isEmpty && texts.isEmpty) return;
    for (final s in strokes) {
      _annotations.put(s.markDeleted(now));
    }
    for (final t in texts) {
      _annotations.putText(t.copyWith(deleted: true, modifiedAt: now));
    }
    _push(_UndoEntry(removed: strokes, removedTexts: texts));
  }

  bool pageHasAnnotations(int page) =>
      _annotations.visibleStrokesOn(page).isNotEmpty || _annotations.visibleTextsOn(page).isNotEmpty;

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
    to.add(inverse);
    _changed();
  }

  /// Ältere Einträge im Verlauf zeigen auf die alte ID – auf die Kopie umbiegen,
  /// damit z. B. "Zeichnen rückgängig" danach den wiederhergestellten Strich trifft.
  void _renameInHistory(String oldId, String newId) {
    for (final e in [..._undo, ..._redo]) {
      for (final list in [e.added, e.addedTexts]) {
        final i = list.indexOf(oldId);
        if (i >= 0) list[i] = newId;
      }
      for (var i = 0; i < e.textsBefore.length; i++) {
        if (e.textsBefore[i].id == oldId) e.textsBefore[i] = e.textsBefore[i].copyWith(id: newId);
      }
    }
  }

  void _push(_UndoEntry e) {
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
