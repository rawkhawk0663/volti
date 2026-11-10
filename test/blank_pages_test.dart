import 'package:flutter_test/flutter_test.dart';
import 'package:volti/core/library/page_setup.dart';

void main() {
  test('Leere Seite einfügen: eigene Nummer, nie doppelt vergeben, übersteht Speichern', () {
    var s = PageSetup.empty;
    final (a, first) = s.withBlankAt(1, 3);
    expect(a.pages(3), [1, first, 2, 3]);
    expect(PageSetup.isBlank(first), isTrue);
    expect(PageSetup.sizeSource(first), 1);

    // Entfernen und neu einfügen: neue Nummer (alte Notizen tauchen nicht auf).
    s = a.withOrder([1, 2, 3]);
    final (b, second) = s.withBlankAt(3, 3);
    expect(second, isNot(first));
    expect(b.pages(3), [1, 2, 3, second]);

    final back = PageSetup.fromJson(b.toJson());
    expect(back.pages(3), [1, 2, 3, second]);
    expect(back.blanks, 2);
  });

  test('Unbekannte leere Seiten werden ignoriert, Zuschnitt behält die Zählung', () {
    final s = const PageSetup(order: [1, PageSetup.blankBase + 5], blanks: 1);
    expect(s.pages(2), [1]);
    final (t, _) = s.withBlankAt(0, 2);
    expect(t.withCrop(1, const PageCrop(left: 0.1)).blanks, 2);
    expect(t.reset().blanks, 2);
  });
}
