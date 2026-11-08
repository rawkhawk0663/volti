import 'package:flutter_test/flutter_test.dart';
import 'package:volti/features/viewer/page_flow.dart';

void main() {
  // Setlist: Song A (3 Seiten), Song B (1 Seite), Song C (2 Seiten)
  final counts = [3, 1, 2];
  final flow = PageFlow(pieceCount: 3, pageCount: (i) => counts[i]);
  const s = PageSlot.new;

  test('Eine Seite: Blättern über Songgrenzen', () {
    expect(flow.next(s(0, 3), twoUp: false), s(1, 1));
    expect(flow.previous(s(1, 1), twoUp: false), s(0, 3));
    expect(flow.next(s(2, 2), twoUp: false), isNull);
    expect(flow.previous(s(0, 1), twoUp: false), isNull);
  });

  test('Zwei Seiten: rechts steht schon der nächste Song', () {
    expect(flow.rightOf(s(0, 3)), s(1, 1), reason: 'letzte Seite A links, B rechts');
    expect(flow.rightOf(s(1, 1)), s(2, 1), reason: 'B ist einseitig → C rechts');
    expect(flow.rightOf(s(2, 2)), isNull);
  });

  test('Zwei Seiten: weiter und zurück jeweils um zwei Seiten', () {
    var left = s(0, 1); // A1 | A2
    left = flow.next(left, twoUp: true)!; // A3 | B1
    expect(left, s(0, 3));
    left = flow.next(left, twoUp: true)!; // C1 | C2
    expect(left, s(2, 1));
    expect(flow.next(left, twoUp: true), isNull);
    left = flow.previous(left, twoUp: true)!; // A3 | B1
    expect(left, s(0, 3));
    left = flow.previous(left, twoUp: true)!; // A1 | A2
    expect(left, s(0, 1));
  });

  test('Am Anfang eine Seite zurück, wenn zwei nicht gehen', () {
    expect(flow.previous(s(0, 2), twoUp: true), s(0, 1));
  });

  test('Unbekannte Seitenzahl (Stück noch nicht geladen) → kein Sprung', () {
    final partial = PageFlow(pieceCount: 2, pageCount: (i) => i == 0 ? null : 2);
    expect(partial.after(s(0, 1)), isNull);
    expect(partial.before(s(1, 1)), isNull);
  });
}
