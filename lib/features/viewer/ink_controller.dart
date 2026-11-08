import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/ink/score_annotations.dart';
import '../../core/ink/stroke.dart';
import '../../core/ink/text_note.dart';
import '../../core/library/sidecar_store.dart';

/// Was der Stift gerade tut.
enum ToolMode { read, pen, highlighter, eraser, text }

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

  ToolMode mode = ToolMode.read;
  int penColor = 0xFF1B1B1B;
  static const int highlighterColor = 0x99FFE066;

  /// Grundbreiten relativ zur Seitenbreite.
  static const double penWidth = 0.003;
  static const double highlighterWidth = 0.014;

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

  void setMode(ToolMode m) {
    mode = m;
    notifyListeners();
  }

  void setPenColor(int color) {
    penColor = color;
    if (mode != ToolMode.pen && mode != ToolMode.text) mode = ToolMode.pen;
    notifyListeners();
  }

  /// Fügt einen fertig gezeichneten Strich hinzu.
  void addStroke({required int page, required InkTool tool, required List<InkPoint> points}) {
    if (points.isEmpty) return;
    final stroke = Stroke(
      id: _uuid.v4(),
      page: page,
      tool: tool,
      color: tool == InkTool.highlighter ? highlighterColor : penColor,
      width: tool == InkTool.highlighter ? highlighterWidth : penWidth,
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

  /// Schriftgrösse für neue Text-Notizen (relativ zur Seitenbreite).
  double textSize = textSizes[1];
  static const textSizes = [0.016, 0.022, 0.032];

  void setTextSize(double size) {
    textSize = size;
    notifyListeners();
  }

  /// Neue Text-Notiz. Gibt ihre ID zurück (null bei leerem Text).
  String? addText({required int page, required double x, required double y, required String text}) {
    if (text.trim().isEmpty) return null;
    final note = TextNote(
      id: _uuid.v4(),
      page: page,
      x: x,
      y: y,
      text: text.trimRight(),
      size: textSize,
      color: penColor,
      createdAt: DateTime.now().toUtc(),
    );
    _annotations.putText(note);
    _push(_UndoEntry(addedTexts: [note.id]));
    return note.id;
  }

  /// Text ändern und/oder verschieben. Leerer Text löscht die Notiz.
  void updateText(String id, {String? text, double? x, double? y}) {
    final before = _annotations.text(id);
    if (before == null || before.deleted) return;
    if (text != null && text.trim().isEmpty) {
      deleteTexts([before]);
      return;
    }
    final after = before.copyWith(text: text?.trimRight(), x: x, y: y, modifiedAt: DateTime.now().toUtc());
    if (after.text == before.text && after.x == before.x && after.y == before.y) return;
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
