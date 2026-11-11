import 'package:flutter_test/flutter_test.dart';
import 'package:volti/app/updater.dart';

void main() {
  test('Versionsnummern werden richtig gelesen und verglichen', () {
    expect(Updater.numberOf('v0.1.42'), 42);
    expect(Updater.numberOf('0.1.7'), 7);
    expect(Updater.numberOf('Testversion'), isNull);
    final u = UpdateInfo(tag: 'v0.1.100', number: 100, page: Uri.parse('https://example.org'));
    // Eine lokal gebaute Testversion gilt als Nummer 0 – also ist alles neuer.
    expect(Updater.isNewer(u), isTrue);
  });
}
