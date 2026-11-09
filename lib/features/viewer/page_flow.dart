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

  /// Nächste Ansicht.
  ///
  /// Alle Stücke verhalten sich wie ein einziges, durchgehendes PDF:
  /// Es geht immer genau **eine** Seite weiter. In der Doppelansicht rutscht
  /// die rechte Seite also nach links, und rechts erscheint die nächste.
  /// So sieht man jeden Song vollständig und jeden Songübergang.
  ///
  /// Doppelansicht: Ist rechts schon die allerletzte Seite, geht es nicht
  /// weiter (sonst bliebe rechts eine leere Hälfte).
  PageSlot? next(PageSlot left, {required bool twoUp}) {
    final one = after(left);
    if (!twoUp || one == null) return one;
    return after(one) == null ? null : one;
  }

  /// Vorherige Ansicht: eine Seite zurück.
  PageSlot? previous(PageSlot left, {required bool twoUp}) => before(left);
}
