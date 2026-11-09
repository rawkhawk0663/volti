import 'package:flutter_test/flutter_test.dart';
import 'package:volti/core/ink/custom_stamps.dart';
import 'package:volti/core/ink/navigation_marks.dart';
import 'package:volti/core/ink/score_annotations.dart';
import 'package:volti/core/library/page_setup.dart';
import 'package:volti/core/pdf/systems.dart';
import 'package:volti/features/viewer/page_export.dart';

void main() {
  test('Notenzeilen werden an den weissen Lücken getrennt', () {
    const w = 100, h = 400;
    final px = List<int>.filled(w * h * 4, 255);
    void band(int from, int to) {
      for (var y = from; y < to; y++) {
        for (var x = 10; x < 90; x++) {
          final i = (y * w + x) * 4;
          px[i] = px[i + 1] = px[i + 2] = 0;
        }
      }
    }

    band(40, 80); // System 1
    band(84, 90); // Liedtext dicht darunter → gehört dazu
    band(150, 200); // System 2
    band(300, 340); // System 3
    px[(380 * w + 50) * 4] = 0; // Staub
    final s = findSystems(px, w, h);
    expect(s.length, 3);
    expect(s[0].top, lessThan(40 / h));
    expect(s[0].bottom, greaterThan(90 / h), reason: 'Liedtext bleibt beim System');
    expect(s[1].top, greaterThan(90 / h));
    expect(s[2].bottom, lessThan(380 / h), reason: 'Staub ist kein System');
  });

  test('Eng gesetzte Systeme werden über die Notenlinien getrennt, Klavier bleibt zusammen', () {
    const w = 200, h = 600;
    final px = List<int>.filled(w * h * 4, 255);
    void dark(int x0, int x1, int y0, int y1) {
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          final i = (y * w + x) * 4;
          px[i] = px[i + 1] = px[i + 2] = 0;
        }
      }
    }

    void staff(int top) {
      for (var k = 0; k < 5; k++) {
        dark(10, 190, top + k * 8, top + k * 8 + 1);
      }
    }

    // System 1 und 2 ohne Lücke: Notenhälse reichen fast bis ins nächste
    staff(50);
    dark(60, 62, 20, 140);
    staff(130);
    dark(100, 102, 120, 210);
    // Klavier: zwei Systeme mit durchgehenden Taktstrichen
    staff(300);
    staff(360);
    for (final x in [40, 120, 185]) {
      dark(x, x + 2, 300, 393);
    }
    final s = findSystems(px, w, h);
    expect(s.length, 3, reason: 'zwei einzelne Systeme + ein Klaviersystem: $s');
    expect(s[0].bottom * h, inInclusiveRange(84, 130));
    expect(s[2].top * h, lessThan(300));
    expect(s[2].bottom * h, greaterThan(392));
  });

  test('Lesezeichen-Bereich und Notenausschnitt', () {
    final a = ScoreAnnotations()
      ..putBookmark(Bookmark(id: 'b', name: 'Lied', page: 3, endPage: 4, createdAt: DateTime.utc(2030)));
    expect(shownPages(PageSetup.empty, 6, a, 'b'), [3, 4]);
    expect(shownPages(PageSetup.empty, 6, a, null), [1, 2, 3, 4, 5, 6]);
    expect(shownPages(PageSetup.empty.withOrder([4, 3, 2]), 6, a, 'b'), [3], reason: 'Bereich in Anzeige-Reihenfolge');

    final s = CustomStamp(
      id: 's',
      name: 'Takte',
      anchorX: 0.5,
      anchorY: 0.5,
      aspect: 3,
      createdAt: DateTime.utc(2030),
      snippet: true,
    );
    expect(CustomStamp.fromJson(s.toJson()).snippet, isTrue);
    expect(s.copyWith(name: 'x').snippet, isTrue);
  });
}
