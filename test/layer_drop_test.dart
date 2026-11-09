import 'package:flutter_test/flutter_test.dart';
import 'package:volti/core/ink/layer_drop.dart';

void main() {
  // Probe (Gruppe) mit Dynamik und Finger, darunter Standard und Extra.
  const rows = <LayerRow>[
    (id: 'probe', isGroup: true, group: null),
    (id: 'dyn', isGroup: false, group: 'probe'),
    (id: 'finger', isGroup: false, group: 'probe'),
    (id: 'std', isGroup: false, group: null),
    (id: 'extra', isGroup: false, group: null),
  ];
  String show(List<({String id, String? parent})> l) => l.map((e) => e.parent == null ? e.id : '  ${e.id}').join(',');

  test('Unter einen Gruppen-Kopf ziehen legt die Ebene oben in die Gruppe', () {
    final d = planLayerDrop(rows, 'extra', 'probe', lowerHalf: true);
    expect(d.group, 'probe');
    expect(show(applyLayerDrop(rows, 'extra', d)), 'probe,  extra,  dyn,  finger,std');
  });

  test('Zwischen zwei Ebenen einer Gruppe bleibt sie in der Gruppe', () {
    final d = planLayerDrop(rows, 'std', 'finger', lowerHalf: false);
    expect(show(applyLayerDrop(rows, 'std', d)), 'probe,  dyn,  std,  finger,extra');
  });

  test('Unter der letzten Ebene nach links ziehen nimmt sie aus der Gruppe', () {
    final d = planLayerDrop(rows, 'dyn', 'finger', lowerHalf: true, outdent: true);
    expect(d.group, isNull);
    expect(show(applyLayerDrop(rows, 'dyn', d)), 'probe,  finger,dyn,std,extra');
  });

  test('Über den Gruppen-Kopf ziehen: oberhalb der Gruppe, ohne Gruppe', () {
    final d = planLayerDrop(rows, 'finger', 'probe', lowerHalf: false);
    expect(show(applyLayerDrop(rows, 'finger', d)), 'finger,probe,  dyn,std,extra');
  });

  test('Eine Gruppe nimmt ihre Ebenen mit und landet nie in einer Gruppe', () {
    final d = planLayerDrop(rows, 'probe', 'extra', lowerHalf: true);
    expect(show(applyLayerDrop(rows, 'probe', d)), 'std,extra,probe,  dyn,  finger');
    final into = planLayerDrop(rows, 'probe', 'dyn', lowerHalf: false);
    expect(into.group, isNull);
  });
}
