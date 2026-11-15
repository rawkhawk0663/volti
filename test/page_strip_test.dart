import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volti/features/viewer/page_strip.dart';

void main() {
  Widget strip(int count, Set<int> current, {bool visible = true}) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: PageStrip(count: count, current: current, visible: visible, thumb: (_) => null, onTap: (_) {}),
      ),
    ),
  );

  double centerOf(WidgetTester t, String label) => t.getCenter(find.text(label)).dx;

  testWidgets('die aktuelle Seite steht immer in der Mitte', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    const mid = 600.0;

    // Erste Seite: in der Mitte, links ist das Dock leer.
    await t.pumpWidget(strip(12, {1}));
    expect(centerOf(t, '1'), closeTo(mid, 0.5));

    // Weiterblättern: die neue Seite rückt in die Mitte.
    await t.pumpWidget(strip(12, {7}));
    await t.pumpAndSettle();
    expect(centerOf(t, '7'), closeTo(mid, 0.5));

    // Letzte Seite: ebenfalls in der Mitte.
    await t.pumpWidget(strip(12, {12}));
    await t.pumpAndSettle();
    expect(centerOf(t, '12'), closeTo(mid, 0.5));

    // Zwei Seiten nebeneinander: die Mitte liegt zwischen beiden.
    await t.pumpWidget(strip(12, {3, 4}));
    await t.pumpAndSettle();
    expect((centerOf(t, '3') + centerOf(t, '4')) / 2, closeTo(mid, 0.5));
  });

  testWidgets('nach eigenem Wischen steht sie beim Einblenden wieder in der Mitte', (t) async {
    await t.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(strip(20, {5}));
    await t.drag(find.byType(ListView), const Offset(-300, 0));
    await t.pumpAndSettle();
    expect(centerOf(t, '5'), isNot(closeTo(600, 50)));
    await t.pumpWidget(strip(20, {5}, visible: false));
    await t.pumpWidget(strip(20, {5}));
    await t.pumpAndSettle();
    expect(centerOf(t, '5'), closeTo(600, 0.5));
  });

  testWidgets('die aktuelle Seite ist etwas grösser', (t) async {
    await t.pumpWidget(strip(5, {2}));
    final scales = t.widgetList<AnimatedScale>(find.byType(AnimatedScale)).map((a) => a.scale).toList();
    expect(scales.where((s) => s > 1).length, 1);
    expect(scales.reduce((a, b) => a > b ? a : b), closeTo(1.14, 0.001));
  });
}
