import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:volti/core/ink/annotation_layer.dart';
import 'package:volti/core/ink/score_annotations.dart';
import 'package:volti/core/ink/selection.dart';
import 'package:volti/core/ink/stroke.dart';
import 'package:volti/core/library/sidecar_store.dart';
import 'package:volti/features/viewer/ink_controller.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('volti_layers'));
  tearDown(() => dir.deleteSync(recursive: true));

  void line(InkController c, double y, {int page = 1}) => c.addStroke(
    page: page,
    tool: InkTool.pen,
    color: 0xFF000000,
    width: 0.004,
    points: [InkPoint(0.2, y, 0.5), InkPoint(0.4, y, 0.5)],
  );

  test('Ohne Ebenen: alles liegt auf der Grund-Ebene (auch alte Dateien)', () {
    final a = ScoreAnnotations.fromJson({
      'strokes': [
        {
          'id': 's1',
          'page': 1,
          'tool': 'pen',
          'color': 0xFF000000,
          'width': 0.003,
          'created': '2025-01-01T00:00:00Z',
          'points': [
            [0.1, 0.1, 0.5],
          ],
        },
      ],
    });
    expect(a.layers.map((l) => l.id), [kDefaultLayer]);
    expect(a.resolveLayer(a['s1']!.layer), kDefaultLayer);
    expect(a.visibleStrokesOn(1).length, 1);
  });

  test('Neue Ebene wird aktiv, Gezeichnetes landet darauf, Ausblenden versteckt es', () {
    final c = InkController(pdfPath: '${dir.path}/x.pdf');
    line(c, 0.1);
    final finger = c.addLayer('Fingersätze');
    expect(c.activeLayer, finger);
    line(c, 0.2);
    line(c, 0.3, page: 2);
    expect(c.countOnLayer(finger), 2, reason: 'auf allen Seiten');
    expect(c.countOnLayer(kDefaultLayer), 1);

    c.setLayerVisible(finger, false);
    expect(c.annotations.visibleStrokesOn(1).length, 1, reason: 'nur noch die Grund-Ebene');
    expect(c.annotations.visibleStrokesOn(2), isEmpty);
    final ids = lassoSelect(c.annotations, 1, const [
      Offset(0, 0),
      Offset(1, 0),
      Offset(1, 1),
      Offset(0, 1),
    ], textBounds: (_) => Rect.zero);
    expect(ids.strokes.length, 1, reason: 'Ausgeblendetes lässt sich nicht auswählen');

    // Weiterzeichnen auf der ausgeblendeten, aktiven Ebene blendet sie wieder ein.
    line(c, 0.4);
    expect(c.annotations.isLayerVisible(finger), isTrue);
    expect(c.annotations.visibleStrokesOn(1).length, 3);
    c.dispose();
  });

  test('Reihenfolge, Zusammenführen, Löschen, Duplizieren', () {
    final c = InkController(pdfPath: '${dir.path}/x.pdf');
    final a = c.addLayer('A');
    line(c, 0.1);
    final b = c.addLayer('B');
    line(c, 0.2);
    line(c, 0.3);
    expect(c.layers.map((l) => l.name), ['Standard', 'A', 'B']);

    c.moveLayer(b, 0);
    expect(c.layers.map((l) => l.name), ['B', 'Standard', 'A']);

    c.mergeLayer(b, a);
    expect(c.layers.map((l) => l.name), ['Standard', 'A']);
    expect(c.countOnLayer(a), 3);
    expect(c.activeLayer, kDefaultLayer, reason: 'aktive Ebene war B');

    final copy = c.duplicateLayer(a);
    expect(c.layers.map((l) => l.name), ['Standard', 'A', 'A (Kopie)']);
    expect(c.countOnLayer(copy), 3);
    expect(c.annotations.visibleStrokesOn(1).length, 6);

    c.deleteLayer(copy);
    expect(c.annotations.visibleStrokesOn(1).length, 3);
    expect(c.layers.length, 2);
    c.undo(); // Ebene und Inhalt kommen zurück – in einem Schritt
    expect(c.annotations.visibleStrokesOn(1).length, 6);
    expect(c.layers.map((l) => l.name), ['Standard', 'A', 'A (Kopie)']);
    expect(c.countOnLayer(copy), 3);

    c.deleteLayer(kDefaultLayer);
    expect(c.layers.length, 3, reason: 'Grund-Ebene lässt sich nicht löschen');
    c.dispose();
  });

  test('Auswahl auf eine andere Ebene legen, rückgängig', () {
    final c = InkController(pdfPath: '${dir.path}/x.pdf');
    line(c, 0.1);
    final s = c.annotations.visibleStrokesOn(1).single;
    final dyn = c.addLayer('Dynamik');
    c.moveToLayer(SelectionIds(strokes: {s.id}), dyn);
    expect(c.annotations[s.id]!.layer, dyn);
    expect(c.annotations[s.id]!.id, s.id, reason: 'derselbe Strich');
    c.undo();
    expect(c.annotations.resolveLayer(c.annotations[s.id]!.layer), kDefaultLayer);
    c.dispose();
  });

  test('Ebenen werden gespeichert und zwischen Geräten zusammengeführt', () async {
    final pdf = '${dir.path}/x.pdf';
    final c = InkController(pdfPath: pdf);
    final id = c.addLayer('Probe');
    line(c, 0.1);
    await c.save();
    final loaded = (await const SidecarStore().load(pdf)).annotations;
    expect(loaded.layers.map((l) => l.name), ['Standard', 'Probe']);
    expect(loaded.resolveLayer(loaded.visibleStrokesOn(1).single.layer), id);

    // Gerät A benennt um, Gerät B blendet später aus: Die jüngste Fassung gewinnt.
    final base = loaded.layer(id)!;
    final a = ScoreAnnotations()..putLayer(base.copyWith(name: 'Probe 1', modifiedAt: DateTime.utc(2030, 1, 1)));
    final b = ScoreAnnotations()..putLayer(base.copyWith(visible: false, modifiedAt: DateTime.utc(2030, 1, 2)));
    final m = ScoreAnnotations.merge(a, b);
    expect(m.layer(id)!.visible, isFalse);
    expect(ScoreAnnotations.merge(b, a).layer(id)!.visible, isFalse, reason: 'unabhängig von der Reihenfolge');

    // Auch beim Löschen gewinnt die jüngste Fassung (so geht "Rückgängig").
    final del = ScoreAnnotations()..putLayer(base.copyWith(deleted: true, modifiedAt: DateTime.utc(2031)));
    expect(ScoreAnnotations.merge(m, del).layers.map((l) => l.id), [kDefaultLayer]);
    final older = ScoreAnnotations()..putLayer(base.copyWith(deleted: true, modifiedAt: DateTime.utc(2029)));
    expect(ScoreAnnotations.merge(m, older).layer(id)!.deleted, isFalse);
    c.dispose();
  });

  test('Gruppen: ausblenden blendet alle Ebenen darin aus; Rückgängig für Ebenen', () {
    final c = InkController(pdfPath: '${dir.path}/x.pdf');
    final g = c.addGroup('Probe');
    final a = c.addLayer('Fingersätze', group: g);
    line(c, 0.1);
    final b = c.addLayer('Dynamik', group: g);
    line(c, 0.2);
    c.activeLayer = kDefaultLayer;
    line(c, 0.3);
    expect(c.annotations.outline().map((r) => '${'  ' * r.depth}${r.layer.name}'), [
      'Probe',
      '  Dynamik',
      '  Fingersätze',
      'Standard',
    ]);
    expect(c.countOnLayer(g), 2);

    c.setLayerVisible(g, false);
    expect(c.annotations.visibleStrokesOn(1).length, 1, reason: 'ganze Gruppe aus');
    c.setLayerVisible(g, true);
    c.setLayerVisible(b, false);
    expect(c.annotations.visibleStrokesOn(1).length, 2, reason: 'einzelne Ebene in der Gruppe aus');
    c.setLayerVisible(b, true);

    // Aus der Gruppe nehmen und wieder zurück (rückgängig)
    c.moveLayerToGroup(a, null);
    expect(c.annotations.groupOf(c.annotations.layer(a)!), isNull);
    c.undo();
    expect(c.annotations.groupOf(c.annotations.layer(a)!)?.id, g);

    // Umbenennen rückgängig
    c.renameLayer(a, 'Finger');
    c.undo();
    expect(c.annotations.layer(a)!.name, 'Fingersätze');

    // Gruppe löschen: Ebenen und Inhalt weg – ein Rückgängig holt alles zurück
    c.deleteLayer(g);
    expect(c.annotations.visibleStrokesOn(1).length, 1);
    expect(c.layers.length, 1);
    c.undo();
    expect(c.annotations.visibleStrokesOn(1).length, 3);
    expect(c.layers.length, 4);

    // Auflösen: Ebenen bleiben, ohne Gruppe
    c.dissolveGroup(g);
    expect(c.layers.map((l) => l.name).toSet(), {'Standard', 'Fingersätze', 'Dynamik'});
    expect(c.annotations.visibleStrokesOn(1).length, 3);
    c.undo();
    expect(c.annotations.layer(g)!.deleted, isFalse);

    // Neue Ebene rückgängig: verschwindet wieder
    final n = c.addLayer('Neu');
    expect(c.activeLayer, n);
    c.undo();
    expect(c.layers.any((l) => l.id == n), isFalse);
    expect(c.activeLayer, kDefaultLayer);
    c.dispose();
  });
}
