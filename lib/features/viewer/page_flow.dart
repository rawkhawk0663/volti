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

  /// Nächste Ansicht. Bei zwei Seiten geht es um zwei Seiten weiter, über
  /// Stückgrenzen hinweg: Ist ein Song nur eine Seite lang, steht rechts schon
  /// der nächste.
  PageSlot? next(PageSlot left, {required bool twoUp}) {
    if (!twoUp) return after(left);
    final right = after(left);
    return right == null ? null : after(right);
  }

  /// Vorherige Ansicht (bei zwei Seiten zwei zurück, am Anfang eine).
  PageSlot? previous(PageSlot left, {required bool twoUp}) {
    final one = before(left);
    if (!twoUp || one == null) return one;
    return before(one) ?? one;
  }
}
