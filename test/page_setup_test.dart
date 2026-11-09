import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volti/core/ink/score_annotations.dart';
import 'package:volti/core/ink/stroke.dart';
import 'package:volti/core/library/page_setup.dart';
import 'package:volti/core/library/sidecar_store.dart';
import 'package:volti/features/viewer/cropped_page.dart';

void main() {
  group('Reihenfolge', () {
    test('Ohne Einrichtung: alle Seiten in PDF-Reihenfolge', () {
      expect(PageSetup.empty.pages(3), [1, 2, 3]);
      expect(PageSetup.empty.isDefault, isTrue);
    });

    test('Umordnen, ausblenden, doppelt zeigen; Ungültiges fällt weg', () {
      final s = PageSetup.empty.withOrder([3, 1, 1, 7]);
      expect(s.pages(3), [3, 1, 1], reason: 'Seite 7 gibt es nicht');
      expect(PageSetup.empty.withOrder([9]).pages(2), [1, 2], reason: 'nie ganz leer');
    });
  });

  group('Zuschnitt', () {
    test('Seitenverhältnis nach Zuschnitt und Drehung', () {
      const a4 = 210 / 297;
      const half = PageCrop(top: 0.5); // untere Hälfte
      expect(half.displayAspect(a4), closeTo(a4 * 2, 1e-9));
      expect(half.copyWith(quarterTurns: 1).displayAspect(a4), closeTo(1 / (a4 * 2), 1e-9));
    });

    test('Werte werden begrenzt', () {
      final c = const PageCrop(left: -0.2, right: 0.05, top: 0.3, bottom: 2).normalized();
      expect(c.left, 0);
      expect(c.right, greaterThanOrEqualTo(0.1));
      expect(c.bottom, 1);
      expect(const PageCrop().copyWith(skew: 30).skew, PageCrop.maxSkew);
      expect(const PageCrop().copyWith(quarterTurns: 5).quarterTurns, 1);
    });

    test('Weisse Ränder finden', () {
      const w = 100, h = 200;
      final px = List<int>.filled(w * h * 4, 255);
      for (var y = 40; y < 160; y++) {
        for (var x = 10; x < 90; x++) {
          final i = (y * w + x) * 4;
          px[i] = px[i + 1] = px[i + 2] = 0;
        }
      }
      // ein einzelnes Staubkorn am Rand zählt nicht
      px[(5 * w + 2) * 4] = 0;
      final c = findContentBounds(px, w, h, margin: 0)!;
      expect(c.left, closeTo(0.1, 1e-9));
      expect(c.right, closeTo(0.9, 1e-9));
      expect(c.top, closeTo(0.2, 1e-9));
      expect(c.bottom, closeTo(0.8, 1e-9));
      expect(findContentBounds(List<int>.filled(w * h * 4, 255), w, h), isNull, reason: 'leere Seite');
    });
  });

  group('Speichern und Sync', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('volti_pages'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('Seiten-Einrichtung wird gespeichert, Anmerkungen bleiben', () async {
      final pdf = '${dir.path}/x.pdf';
      const store = SidecarStore();
      await store.save(
        pdf,
        annotations: ScoreAnnotations([
          Stroke(
            id: 's',
            page: 2,
            tool: InkTool.pen,
            color: 0xFF000000,
            width: 0.003,
            points: [InkPoint(0.1, 0.1, 0.5)],
            createdAt: DateTime.utc(2025),
          ),
        ]),
      );
      final setup = PageSetup.empty
          .withOrder([2, 1])
          .withCrop(2, const PageCrop(top: 0.1, bottom: 0.9, quarterTurns: 1, skew: 1.5));
      await store.save(pdf, pages: setup);
      final loaded = await store.load(pdf);
      expect(loaded.pages.pages(2), [2, 1]);
      expect(loaded.pages.cropOf(2), const PageCrop(top: 0.1, bottom: 0.9, quarterTurns: 1, skew: 1.5));
      expect(loaded.pages.cropOf(1).isNone, isTrue);
      expect(loaded.annotations.visibleStrokesOn(2).length, 1, reason: 'Anmerkungen unverändert');

      // Ein Speichern nur der Anmerkungen lässt die Seiten-Einrichtung stehen.
      await store.save(pdf, annotations: loaded.annotations);
      expect((await store.load(pdf)).pages.pages(2), [2, 1]);
    });

    test('Jüngste Fassung gewinnt als Ganzes', () {
      final a = PageSetup.empty.withOrder([2, 1], now: DateTime.utc(2030, 1, 1));
      final b = PageSetup.empty.withCrop(1, const PageCrop(left: 0.2), now: DateTime.utc(2030, 1, 2));
      expect(PageSetup.merge(a, b).order, isNull);
      expect(PageSetup.merge(b, a).cropOf(1).left, 0.2);
      expect(PageSetup.merge(PageSetup.empty, a).order, [2, 1]);
      final reset = a.reset(now: DateTime.utc(2030, 2));
      expect(PageSetup.merge(a, reset).isDefault, isTrue, reason: 'Zurücksetzen gewinnt, wenn es jünger ist');
    });
  });

  group('Anzeige', () {
    Future<Offset?> tapAt(WidgetTester t, PageCrop crop, Size size, Offset at) async {
      Offset? hit;
      Size? full;
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: CroppedPage(
              crop: crop,
              size: size,
              page: (s) {
                full = s;
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => hit = Offset(e.localPosition.dx / s.width, e.localPosition.dy / s.height),
                  child: SizedBox.fromSize(size: s),
                );
              },
            ),
          ),
        ),
      );
      expect(full, isNotNull);
      await t.tapAt(at);
      return hit;
    }

    testWidgets('Antippen trifft die richtige Stelle der ganzen Seite', (t) async {
      // Untere rechte Viertel-Seite, angezeigt in 200×200
      final hit = await tapAt(t, const PageCrop(left: 0.5, top: 0.5), const Size(200, 200), const Offset(100, 100));
      expect(hit!.dx, closeTo(0.75, 0.001));
      expect(hit.dy, closeTo(0.75, 0.001));

      // Ganze Seite, um 90° gedreht: oben links der Anzeige = unten links der Seite
      final turned = await tapAt(t, const PageCrop(quarterTurns: 1), const Size(300, 200), const Offset(1, 1));
      expect(turned!.dx, closeTo(0.0, 0.01));
      expect(turned.dy, closeTo(1.0, 0.01));
    });
  });
}
