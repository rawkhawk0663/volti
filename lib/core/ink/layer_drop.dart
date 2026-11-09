/// Eine Zeile der Ebenen-Liste (oben zuerst).
typedef LayerRow = ({String id, bool isGroup, String? group});

/// Wohin eine gezogene Ebene oder Gruppe fallen soll: über oder unter die
/// Zeile [target], und in welche Gruppe ([group], null = keine).
class LayerDrop {
  const LayerDrop({required this.target, required this.after, required this.group});
  final String target;
  final bool after;
  final String? group;

  @override
  bool operator ==(Object other) =>
      other is LayerDrop && other.target == target && other.after == after && other.group == group;

  @override
  int get hashCode => Object.hash(target, after, group);
}

/// Bestimmt, wohin [moved] beim Loslassen über der Zeile [target] fällt.
///
/// * Untere Hälfte eines Gruppen-Kopfs: als oberste Ebene in die Gruppe.
/// * Über/unter einer Ebene in einer Gruppe: in dieselbe Gruppe – ausser man
///   zieht unter der letzten Ebene einer Gruppe nach links ([outdent]), dann
///   kommt sie unter die Gruppe.
/// * Gruppen landen nie in einer Gruppe, sondern davor oder dahinter.
LayerDrop planLayerDrop(
  List<LayerRow> rows,
  String moved,
  String target, {
  required bool lowerHalf,
  bool outdent = false,
}) {
  final m = rows.firstWhere((r) => r.id == moved);
  final t = rows.firstWhere((r) => r.id == target);
  if (m.isGroup) {
    // Gruppen nur zwischen oberste Einträge: auf die Gruppe des Ziels ausweichen.
    final anchor = t.group ?? t.id;
    return LayerDrop(target: anchor, after: t.group != null || lowerHalf, group: null);
  }
  if (t.isGroup) return LayerDrop(target: t.id, after: lowerHalf, group: lowerHalf ? t.id : null);
  if (t.group != null) {
    final siblings = rows.where((r) => r.group == t.group).toList();
    final last = siblings.last.id == t.id;
    if (lowerHalf && last && outdent) return LayerDrop(target: t.group!, after: true, group: null);
    return LayerDrop(target: t.id, after: lowerHalf, group: t.group);
  }
  return LayerDrop(target: t.id, after: lowerHalf, group: null);
}

/// Neue Liste (oben zuerst) nach dem Loslassen: jede Ebene mit ihrer Gruppe.
/// Eine gezogene Gruppe nimmt ihre Ebenen mit.
List<({String id, String? parent})> applyLayerDrop(List<LayerRow> rows, String moved, LayerDrop drop) {
  final m = rows.firstWhere((r) => r.id == moved);
  final block = [
    for (final r in rows)
      if (r.id == moved || (m.isGroup && r.group == moved)) r,
  ];
  final rest = [
    for (final r in rows)
      if (!block.contains(r)) r,
  ];
  final t = rest.indexWhere((r) => r.id == drop.target);
  int at;
  if (t < 0) {
    at = 0;
  } else if (!drop.after) {
    at = t;
  } else if (rest[t].isGroup && drop.group != rest[t].id) {
    // Unter eine Gruppe (nicht hinein): hinter ihre letzte Ebene.
    at = t + 1;
    while (at < rest.length && rest[at].group == rest[t].id) {
      at++;
    }
  } else {
    at = t + 1;
  }
  final placed = [for (final r in block) (id: r.id, isGroup: r.isGroup, group: r.id == moved ? drop.group : r.group)];
  final all = [...rest]..insertAll(at, placed);
  return [for (final r in all) (id: r.id, parent: r.isGroup ? null : r.group)];
}
