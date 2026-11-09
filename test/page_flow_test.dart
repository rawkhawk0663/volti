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

  test('Zwei Seiten: am Songübergang immer letzte + erste Seite zusammen', () {
    // A (3 Seiten), B (1), C (2)
    final views = <PageSlot>[s(0, 1)];
    while (true) {
      final n = flow.next(views.last, twoUp: true);
      if (n == null) break;
      views.add(n);
    }
    // A1|A2 → A3|B1 → B1|C1 → C2
    // (B ist einseitig: B1 kommt nach links, damit man B1 und C1 zusammen sieht.)
    expect(views, [s(0, 1), s(0, 3), s(1, 1), s(2, 2)]);
    // Zurück ergibt genau dieselben Ansichten rückwärts.
    final back = <PageSlot>[views.last];
    while (true) {
      final p = flow.previous(back.last, twoUp: true);
      if (p == null) break;
      back.add(p);
    }
    expect(back, views.reversed.toList());
  });

  test('Auch zwei zweiseitige Songs: A1|A2 → A2|B1 → B2', () {
    final f = PageFlow(pieceCount: 2, pageCount: (i) => 2);
    expect(f.next(s(0, 1), twoUp: true), s(0, 2));
    expect(f.rightOf(s(0, 2)), s(1, 1), reason: 'Übergang: letzte Seite A + erste Seite B');
    expect(f.next(s(0, 2), twoUp: true), s(1, 2));
    expect(f.next(s(1, 2), twoUp: true), isNull);
    expect(f.previous(s(1, 2), twoUp: true), s(0, 2));
    expect(f.previous(s(0, 2), twoUp: true), s(0, 1));
  });

  test('Viele zweiseitige Songs: jeder Übergang ist sichtbar', () {
    final f = PageFlow(pieceCount: 3, pageCount: (i) => 2);
    final pairs = <String>[];
    PageSlot? v = s(0, 1);
    while (v != null) {
      final r = f.rightOf(v);
      pairs.add('${v.piece}/${v.page}|${r == null ? '-' : '${r.piece}/${r.page}'}');
      v = f.next(v, twoUp: true);
    }
    expect(pairs, ['0/1|0/2', '0/2|1/1', '1/2|2/1', '2/2|-']);
  });

  test('Ein einzelnes Stück blättert weiter um zwei Seiten', () {
    final f = PageFlow(pieceCount: 1, pageCount: (i) => 5);
    expect(f.next(s(0, 1), twoUp: true), s(0, 3));
    expect(f.next(s(0, 3), twoUp: true), s(0, 5));
    expect(f.next(s(0, 5), twoUp: true), isNull);
    expect(f.previous(s(0, 5), twoUp: true), s(0, 3));
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
