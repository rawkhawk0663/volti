import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volti/app/l10n.dart';
import 'package:volti/core/ink/stamp_names.dart';

void main() {
  tearDown(() => L10n.language.value = AppLanguage.de);

  test('tr liefert die Sprache der App', () {
    L10n.language.value = AppLanguage.de;
    expect(tr('Bibliothek', 'Library'), 'Bibliothek');
    L10n.language.value = AppLanguage.en;
    expect(tr('Bibliothek', 'Library'), 'Library');
    expect(stampName('Fermate'), 'Fermata');
    expect(stampName('mf'), 'mf');
  });

  test('Sprachcodes', () {
    expect(AppLanguage.fromCode('en'), AppLanguage.en);
    expect(AppLanguage.fromCode('xx'), isNull);
    expect(AppLanguage.en.locale, const Locale('en'));
  });

  testWidgets('Umschalten baut auch Texte neu, die sich sonst nicht neu aufbauen', (t) async {
    L10n.language.value = AppLanguage.de;
    await t.pumpWidget(const MaterialApp(home: _Label()));
    expect(find.text('Einstellungen'), findsOneWidget);
    L10n.set(AppLanguage.en);
    await t.pump();
    expect(find.text('Settings'), findsOneWidget);
  });
}

class _Label extends StatelessWidget {
  const _Label();
  @override
  Widget build(BuildContext context) => Text(tr('Einstellungen', 'Settings'));
}
