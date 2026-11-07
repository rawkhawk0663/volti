import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volti/core/ink/annotation_store.dart';
import 'package:volti/core/ink/score_annotations.dart';
import 'package:volti/core/ink/stroke.dart';
import 'package:volti/features/viewer/ink_controller.dart';

Stroke stroke(String id, {int page = 1, DateTime? at, bool deleted = false}) => Stroke(
      id: id,
      page: page,
      tool: InkTool.pen,
      color: 0xFF000000,
      width: 0.002,
      points: const [InkPoint(0.1, 0.2, 0.5), InkPoint(0.3, 0.4, 0.9)],
      createdAt: at ?? DateTime.utc(2026, 1, 1),
      deleted: deleted,
      modifiedAt: deleted ? DateTime.utc(2026, 1, 2) : null,
    );

Set<String> visibleIds(ScoreAnnotations a, [int page = 1]) => a.visibleStrokesOn(page).map((s) => s.id).toSet();

void main() {
  group('Speicherformat', () {
    test('Strich übersteht Speichern und Laden unverändert', () {
      final a = ScoreAnnotations([stroke('a'), stroke('b', page: 2)]);
      final back = ScoreAnnotations.fromJson(a.toJson());
      expect(visibleIds(back), {'a'});
      expect(visibleIds(back, 2), {'b'});
      final p = back['a']!.points;
      expect(p.length, 2);
      expect(p[1].x, closeTo(0.3, 1e-6));
      expect(p[1].pressure, closeTo(0.9, 1e-6));
    });
  });

  group('Zusammenführen (Sync)', () {
    test('Striche von zwei Geräten werden vereint', () {
      final m = ScoreAnnotations.merge(ScoreAnnotations([stroke('a')]), ScoreAnnotations([stroke('b')]));
      expect(visibleIds(m), {'a', 'b'});
    });

    test('Gelöscht bleibt gelöscht, egal in welcher Reihenfolge', () {
      final live = ScoreAnnotations([stroke('a')]);
      final gone = ScoreAnnotations([stroke('a', deleted: true)]);
      expect(visibleIds(ScoreAnnotations.merge(live, gone)), isEmpty);
      expect(visibleIds(ScoreAnnotations.merge(gone, live)), isEmpty);
    });
  });

  group('Ablage neben dem PDF', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('volti_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('Änderungen eines anderen Geräts gehen beim Speichern nicht verloren', () async {
      const store = AnnotationStore();
      final pdf = '${dir.path}/stueck.pdf';
      // Gerät 1 hat Strich a gespeichert.
      await store.save(pdf, ScoreAnnotations([stroke('a')]));
      // Gerät 2 kennt nur seinen eigenen Strich b und speichert.
      final merged = await store.save(pdf, ScoreAnnotations([stroke('b')]));
      expect(visibleIds(merged), {'a', 'b'});
      expect(visibleIds(await store.load(pdf)), {'a', 'b'});
    });

    test('Beschädigte Datei wird gesichert statt überschrieben', () async {
      const store = AnnotationStore();
      final pdf = '${dir.path}/kaputt.pdf';
      File('$pdf${AnnotationStore.suffix}').writeAsStringSync('{nicht json');
      final a = await store.load(pdf);
      expect(a.isEmpty, isTrue);
      expect(dir.listSync().any((f) => f.path.contains('.defekt-')), isTrue);
    });
  });

  group('Rückgängig / Wiederholen', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('volti_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('Zeichnen, Radieren, Rückgängig, Wiederholen', () async {
      final c = InkController(pdfPath: '${dir.path}/x.pdf');
      const pts = [InkPoint(0.5, 0.5, 0.5)];
      c.addStroke(page: 1, tool: InkTool.pen, points: pts);
      expect(c.annotations.visibleStrokesOn(1).length, 1);

      c.eraseStrokes(c.annotations.visibleStrokesOn(1));
      expect(c.annotations.visibleStrokesOn(1), isEmpty);

      c.undo(); // Radieren rückgängig → Strich wieder da (als Kopie)
      expect(c.annotations.visibleStrokesOn(1).length, 1);

      c.undo(); // Zeichnen rückgängig
      expect(c.annotations.visibleStrokesOn(1), isEmpty);

      c.redo();
      expect(c.annotations.visibleStrokesOn(1).length, 1);

      // Nach dem Speichern ist der Stand derselbe (kein "Wiederauferstehen").
      await c.save();
      expect((await const AnnotationStore().load('${dir.path}/x.pdf')).visibleStrokesOn(1).length, 1);
      c.dispose();
    });
  });
}
