import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volti/core/ink/stroke.dart';
import 'package:volti/core/library/sidecar_store.dart';
import 'package:volti/features/viewer/ink_controller.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('volti_scope'));
  tearDown(() => dir.deleteSync(recursive: true));

  void line(InkController c) => c.addStroke(
    page: 1,
    tool: InkTool.pen,
    color: 0xFF000000,
    width: 0.01,
    points: const [InkPoint(0.1, 0.1, 0.5), InkPoint(0.9, 0.1, 0.5)],
  );

  test('Notizen in einer Setlist bleiben in der Setlist, Bibliotheks-Notizen erscheinen überall', () async {
    final pdf = '${dir.path}/Lied.pdf';

    // In der Bibliothek: gehört zum Song.
    final lib = InkController(pdfPath: pdf);
    await lib.load();
    line(lib);
    await lib.save();

    // In Setlist A: neue Notizen landen auf der Setlist-Ebene, auch eine weitere Ebene.
    final a = InkController(pdfPath: pdf, scope: 'A', scopeName: 'Gottesdienst');
    await a.load();
    expect(a.visibleStrokesCount(), 1, reason: 'Bibliotheks-Notiz ist sichtbar');
    line(a);
    final second = a.addLayer('Bläser');
    line(a);
    expect(a.annotations.layer(second)!.scope, 'A');
    await a.save();
    expect(a.visibleStrokesCount(), 3);

    // Setlist B sieht nur die Bibliotheks-Notiz.
    final b = InkController(pdfPath: pdf, scope: 'B', scopeName: 'Konzert');
    await b.load();
    expect(b.visibleStrokesCount(), 1);
    expect(b.layers.where((l) => l.scope == 'A'), isEmpty);

    // Die Bibliothek ebenfalls – auch nach dem Neuladen.
    final again = (await const SidecarStore().load(pdf)).annotations;
    expect(again.visibleStrokesOn(1).length, 1);
    again.viewScope = 'A';
    expect(again.visibleStrokesOn(1).length, 3);
    for (final c in [lib, a, b]) {
      c.dispose();
    }
  });
}

extension on InkController {
  int visibleStrokesCount() => annotations.visibleStrokesOn(1).length;
}
