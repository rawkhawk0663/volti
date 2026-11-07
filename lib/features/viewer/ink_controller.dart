import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/ink/annotation_store.dart';
import '../../core/ink/score_annotations.dart';
import '../../core/ink/stroke.dart';

/// Was der Stift gerade tut.
enum ToolMode { read, pen, highlighter, eraser }

/// Eine rückgängig machbare Aktion: welche Striche dazukamen und welche
/// entfernt wurden.
class _UndoEntry {
  _UndoEntry(this.added, this.removed);
  final List<String> added;
  final List<Stroke> removed;
}

/// Verwaltet die Anmerkungen eines Stücks: Zeichnen, Radieren,
/// Rückgängig/Wiederholen und automatisches Speichern.
class InkController extends ChangeNotifier {
  InkController({required this.pdfPath, AnnotationStore? store}) : _store = store ?? const AnnotationStore();

  final String pdfPath;
  final AnnotationStore _store;
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
    _annotations = await _store.load(pdfPath);
    notifyListeners();
  }

  void setMode(ToolMode m) {
    mode = m;
    notifyListeners();
  }

  void setPenColor(int color) {
    penColor = color;
    if (mode != ToolMode.pen) mode = ToolMode.pen;
    notifyListeners();
  }

  /// Fügt einen fertig gezeichneten Strich hinzu.
  void addStroke({
    required int page,
    required InkTool tool,
    required List<InkPoint> points,
  }) {
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
    _push(_UndoEntry([stroke.id], []));
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
    _push(_UndoEntry([], removed));
  }

  void undo() => _apply(_undo, _redo);
  void redo() => _apply(_redo, _undo);

  /// Kehrt eine Aktion um. Gelöschte Striche kommen als *Kopie mit neuer ID*
  /// zurück – so bleibt das Zusammenführen beim Sync eindeutig
  /// ("gelöscht bleibt gelöscht").
  void _apply(List<_UndoEntry> from, List<_UndoEntry> to) {
    if (from.isEmpty) return;
    final entry = from.removeLast();
    final now = DateTime.now().toUtc();
    final removedNow = <Stroke>[];
    for (final id in entry.added) {
      final s = _annotations[id];
      if (s != null && !s.deleted) {
        _annotations.put(s.markDeleted(now));
        removedNow.add(s);
      }
    }
    final addedNow = <String>[];
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
      addedNow.add(copy.id);
      _renameInHistory(s.id, copy.id);
    }
    to.add(_UndoEntry(addedNow, removedNow));
    _changed();
  }

  /// Ältere Einträge im Verlauf zeigen auf die alte ID – auf die Kopie umbiegen,
  /// damit z. B. "Zeichnen rückgängig" danach den wiederhergestellten Strich trifft.
  void _renameInHistory(String oldId, String newId) {
    for (final e in [..._undo, ..._redo]) {
      final i = e.added.indexOf(oldId);
      if (i >= 0) e.added[i] = newId;
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
      final merged = await _store.save(pdfPath, _annotations);
      // Falls ein anderes Gerät inzwischen etwas ergänzt hat, übernehmen.
      if (merged.allStrokes.length != _annotations.allStrokes.length) {
        _annotations = ScoreAnnotations.merge(_annotations, merged);
      }
      saveError = null;
    } catch (e) {
      _dirty = true;
      saveError = 'Speichern fehlgeschlagen: $e';
    }
    if (!_disposed) notifyListeners();
  }

  bool _disposed = false;

  /// Beim Schliessen werden ungespeicherte Änderungen noch geschrieben.
  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    if (_dirty) unawaited(save());
    super.dispose();
  }
}
