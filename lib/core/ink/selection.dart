import 'dart:ui' show Offset, Rect;

import 'score_annotations.dart';
import 'stamp.dart';
import 'stroke.dart';
import 'text_note.dart';

/// Ausgewählte Elemente einer Seite (Lasso).
class SelectionIds {
  const SelectionIds({this.strokes = const {}, this.stamps = const {}, this.texts = const {}});

  final Set<String> strokes;
  final Set<String> stamps;
  final Set<String> texts;

  bool get isEmpty => strokes.isEmpty && stamps.isEmpty && texts.isEmpty;
  int get count => strokes.length + stamps.length + texts.length;
  bool contains(String id) => strokes.contains(id) || stamps.contains(id) || texts.contains(id);

  /// Nur, was es auf der Seite noch gibt (z. B. nach "Rückgängig").
  SelectionIds liveIn(ScoreAnnotations a) => SelectionIds(
    strokes: {
      for (final id in strokes)
        if (a[id]?.deleted == false) id,
    },
    stamps: {
      for (final id in stamps)
        if (a.stamp(id)?.deleted == false) id,
    },
    texts: {
      for (final id in texts)
        if (a.text(id)?.deleted == false) id,
    },
  );
}

/// Verschieben und Vergrössern einer Auswahl, in normierten Koordinaten.
///
/// Ein Punkt p wird zu `anchor + (p - anchor) * scale + delta`. Weil die
/// Vergrösserung in beide Richtungen gleich ist, bleiben Formen auch auf
/// nicht-quadratischen Seiten unverzerrt.
class SelectionTransform {
  const SelectionTransform({this.delta = Offset.zero, this.scale = 1, this.anchor = Offset.zero});

  final Offset delta;
  final double scale;
  final Offset anchor;

  static const identity = SelectionTransform();

  bool get isIdentity => delta == Offset.zero && scale == 1;

  Offset apply(Offset p) => anchor + (p - anchor) * scale + delta;
}

/// Kopierte Elemente (app-weit, auch in ein anderes Stück einfügbar).
class InkClip {
  const InkClip({this.strokes = const [], this.stamps = const [], this.texts = const []});

  final List<Stroke> strokes;
  final List<Stamp> stamps;
  final List<TextNote> texts;

  bool get isEmpty => strokes.isEmpty && stamps.isEmpty && texts.isEmpty;
}

/// Liegt [p] im Vieleck [poly]? (Strahl-Verfahren)
bool pointInPolygon(Offset p, List<Offset> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) && p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

/// Was liegt im Lasso [poly] (normierte Koordinaten)?
///
/// * Striche: wenn mindestens die Hälfte ihrer Punkte drin liegt – so
///   erwischt man nicht aus Versehen den langen Bogen, den man nur streift.
/// * Stempel: wenn ihre Mitte drin liegt.
/// * Text-Notizen: wenn die Mitte ihrer Fläche drin liegt ([textBounds],
///   normiert).
SelectionIds lassoSelect(
  ScoreAnnotations a,
  int page,
  List<Offset> poly, {
  required Rect Function(TextNote note) textBounds,
}) {
  if (poly.length < 3) return const SelectionIds();
  final strokes = <String>{};
  for (final s in a.visibleStrokesOn(page)) {
    if (s.points.isEmpty) continue;
    var inside = 0;
    for (final p in s.points) {
      if (pointInPolygon(Offset(p.x, p.y), poly)) inside++;
    }
    if (inside * 2 >= s.points.length) strokes.add(s.id);
  }
  final stamps = {
    for (final st in a.visibleStampsOn(page))
      if (pointInPolygon(Offset(st.x, st.y), poly)) st.id,
  };
  final texts = {
    for (final t in a.visibleTextsOn(page))
      if (pointInPolygon(textBounds(t).center, poly)) t.id,
  };
  return SelectionIds(strokes: strokes, stamps: stamps, texts: texts);
}

/// Ersetzt die Farbe, behält aber die Deckkraft (z. B. beim Textmarker).
int recolorKeepingAlpha(int original, int color) => (original & 0xFF000000) | (color & 0x00FFFFFF);
