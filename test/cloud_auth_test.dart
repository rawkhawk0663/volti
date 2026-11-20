import 'package:flutter_test/flutter_test.dart';
import 'package:volti/core/sync/cloud_auth.dart';

void main() {
  test('Anmeldung mit Code: Adresse ohne Rückleitung, mit PKCE und dauerhaftem Zugang', () {
    final auth = OAuthClient.dropbox();
    final url = auth.codeSignInUrl();
    expect(url.host, 'www.dropbox.com');
    final q = url.queryParameters;
    expect(q['response_type'], 'code');
    expect(q['code_challenge_method'], 'S256');
    expect(q['code_challenge'], isNotEmpty);
    expect(q['token_access_type'], 'offline');
    // Dropbox zeigt den Code selbst an: keine Rückmeldung an das Gerät.
    expect(q.containsKey('redirect_uri'), isFalse);
    // Jede Anmeldung bekommt eine neue Prüfung.
    expect(auth.codeSignInUrl().queryParameters['code_challenge'], isNot(q['code_challenge']));
  });

  test('Code einlösen geht erst nach „Bei Dropbox anmelden“, leerer Code wird abgelehnt', () async {
    final auth = OAuthClient.dropbox();
    await expectLater(auth.finishCodeSignIn('abc'), throwsA(isA<CloudAuthException>()));
    auth.codeSignInUrl();
    await expectLater(auth.finishCodeSignIn('   '), throwsA(isA<CloudAuthException>()));
  });
}
