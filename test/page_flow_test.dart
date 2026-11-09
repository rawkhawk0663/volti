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

  List<String> walk(PageFlow f, PageSlot start) {
    final pairs = <String>[];
    PageSlot? v = start;
    while (v != null) {
      final r = f.rightOf(v);
      pairs.add('${v.piece}/${v.page}|${r == null ? '-' : '${r.piece}/${r.page}'}');
      v = f.next(v, twoUp: true);
    }
    return pairs;
  }

  test('Zwei Seiten: wie ein einziges PDF, immer eine Seite weiter', () {
    // A (3 Seiten), B (1), C (2)
    expect(walk(flow, s(0, 1)), ['0/1|0/2', '0/2|0/3', '0/3|1/1', '1/1|2/1', '2/1|2/2']);
    // Zurück ergibt genau dieselben Ansichten rückwärts.
    final back = <PageSlot>[s(2, 1)];
    while (true) {
      final p = flow.previous(back.last, twoUp: true);
      if (p == null) break;
      back.add(p);
    }
    expect(back, [s(2, 1), s(1, 1), s(0, 3), s(0, 2), s(0, 1)]);
  });

  test('Mehrere zweiseitige Songs: jeder Song einmal ganz sichtbar', () {
    final f = PageFlow(pieceCount: 3, pageCount: (i) => 2);
    expect(walk(f, s(0, 1)), ['0/1|0/2', '0/2|1/1', '1/1|1/2', '1/2|2/1', '2/1|2/2']);
  });

  test('Ein einzelnes Stück: auch eine Seite weiter, rechts nie leer', () {
    final f = PageFlow(pieceCount: 1, pageCount: (i) => 3);
    expect(f.next(s(0, 1), twoUp: true), s(0, 2));
    expect(f.next(s(0, 2), twoUp: true), isNull);
    expect(f.previous(s(0, 2), twoUp: true), s(0, 1));
    final single = PageFlow(pieceCount: 1, pageCount: (i) => 1);
    expect(single.next(s(0, 1), twoUp: true), isNull);
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
