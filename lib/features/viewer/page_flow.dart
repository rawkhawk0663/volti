/// Eine Seite in einer Folge von Stücken (z. B. einer Setlist).
class PageSlot {
  const PageSlot(this.piece, this.page);

  /// Index des Stücks in der Liste.
  final int piece;

  /// Seite im Stück, beginnend bei 1.
  final int page;

  @override
  bool operator ==(Object other) => other is PageSlot && other.piece == piece && other.page == page;

  @override
  int get hashCode => Object.hash(piece, page);

  @override
  String toString() => '($piece/$page)';
}

/// Blättern über Stückgrenzen hinweg – für eine und für zwei Seiten.
///
/// [pageCount] liefert die Seitenzahl eines Stücks oder `null`, solange das
/// Stück noch nicht geladen ist. [pieceCount] ist die Anzahl Stücke.
class PageFlow {
  const PageFlow({required this.pieceCount, required this.pageCount});

  final int pieceCount;
  final int? Function(int piece) pageCount;

  /// Seite nach [s] (auch die erste Seite des nächsten Stücks), sonst null.
  /// Ist die Seitenzahl des Stücks noch unbekannt, ebenfalls null.
  PageSlot? after(PageSlot s) {
    final count = pageCount(s.piece);
    if (count == null) return null;
    if (s.page < count) return PageSlot(s.piece, s.page + 1);
    if (s.piece + 1 < pieceCount) return PageSlot(s.piece + 1, 1);
    return null;
  }

  /// Seite vor [s] (auch die letzte Seite des vorherigen Stücks), sonst null.
  /// Braucht die Seitenzahl des vorherigen Stücks; ist sie unbekannt, null.
  PageSlot? before(PageSlot s) {
    if (s.page > 1) return PageSlot(s.piece, s.page - 1);
    if (s.piece == 0) return null;
    final count = pageCount(s.piece - 1);
    if (count == null || count == 0) return null;
    return PageSlot(s.piece - 1, count);
  }

  /// Rechte Seite in der Doppelansicht (null = keine mehr).
  PageSlot? rightOf(PageSlot left) => after(left);

  /// Ist [s] die letzte Seite ihres Stücks, und kommt danach noch ein Stück?
  bool _endsPieceBeforeAnother(PageSlot s) => s.page == pageCount(s.piece) && s.piece + 1 < pieceCount;

  /// Nächste Ansicht.
  ///
  /// Eine Seite: einfach die nächste Seite.
  ///
  /// Zwei Seiten: innerhalb eines Stücks zwei Seiten weiter. Am Ende eines
  /// Stücks gibt es aber **immer** eine Ansicht mit der letzten Seite des
  /// alten und der ersten Seite des neuen Stücks nebeneinander – egal wie
  /// viele Seiten die Stücke haben. Wichtig für Live-Musik: Man sieht den
  /// Übergang.
  PageSlot? next(PageSlot left, {required bool twoUp}) {
    if (!twoUp) return after(left);
    final right = after(left);
    if (right == null) return null;
    // Rechts steht die letzte Seite eines Stücks → sie kommt nach links,
    // rechts erscheint der Anfang des nächsten Stücks.
    if (_endsPieceBeforeAnother(right)) return right;
    return after(right);
  }

  /// Vorherige Ansicht – genau die Ansicht, von der aus "weiter" hierher
  /// führen würde (Übergangsansichten inklusive).
  PageSlot? previous(PageSlot left, {required bool twoUp}) {
    final one = before(left);
    if (!twoUp || one == null) return one;
    final two = before(one);
    if (two != null && next(two, twoUp: true) == left) return two;
    if (next(one, twoUp: true) == left) return one;
    return two ?? one;
  }
}
