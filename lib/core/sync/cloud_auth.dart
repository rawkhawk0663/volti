import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../../app/l10n.dart';

/// Schlüssel der Cloud-Dienste. Sie werden beim Bauen eingesetzt (Geheimnisse
/// im GitHub-Projekt, siehe build.yml) und stecken dann in der App – bei Apps
/// auf dem Gerät ist das üblich und von Dropbox/Google so vorgesehen.
const dropboxAppKey = String.fromEnvironment('DROPBOX_APP_KEY');
const googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
const googleClientSecret = String.fromEnvironment('GOOGLE_CLIENT_SECRET');

/// Fester Anschluss für die Rückmeldung nach der Anmeldung im Browser
/// (bei Dropbox muss die Adresse genau so eingetragen sein).
const oauthPort = 53682;

class CloudAuthException implements Exception {
  CloudAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Anmeldung bei einem Cloud-Dienst (OAuth mit PKCE) und Verwaltung der
/// Zugangsschlüssel. Der langlebige Schlüssel ([refreshToken]) wird auf dem
/// Gerät gespeichert, der kurzlebige ([_access]) nur im Speicher gehalten.
class OAuthClient {
  OAuthClient({
    required this.authorizeUrl,
    required this.tokenUrl,
    required this.clientId,
    required this.redirectUri,
    this.clientSecret,
    this.scope,
    this.extraAuthParams = const {},
    this.refreshToken,
    this.onRefreshToken,
  });

  final String authorizeUrl, tokenUrl, clientId, redirectUri;
  final String? clientSecret, scope;
  final Map<String, String> extraAuthParams;

  String? refreshToken;

  /// Wird aufgerufen, wenn der Dienst einen neuen langlebigen Schlüssel gibt.
  final Future<void> Function(String token)? onRefreshToken;

  String? _access;
  DateTime _accessUntil = DateTime(2000);

  static OAuthClient dropbox({String? refreshToken, Future<void> Function(String)? onRefreshToken}) => OAuthClient(
    authorizeUrl: 'https://www.dropbox.com/oauth2/authorize',
    tokenUrl: 'https://api.dropboxapi.com/oauth2/token',
    clientId: dropboxAppKey,
    redirectUri: 'http://localhost:$oauthPort/',
    extraAuthParams: const {'token_access_type': 'offline'},
    refreshToken: refreshToken,
    onRefreshToken: onRefreshToken,
  );

  static OAuthClient google({String? refreshToken, Future<void> Function(String)? onRefreshToken}) => OAuthClient(
    authorizeUrl: 'https://accounts.google.com/o/oauth2/v2/auth',
    tokenUrl: 'https://oauth2.googleapis.com/token',
    clientId: googleClientId,
    clientSecret: googleClientSecret,
    redirectUri: 'http://127.0.0.1:$oauthPort/',
    // Nur Dateien, die Volti selbst anlegt – Volti sieht sonst nichts im Drive.
    scope: 'https://www.googleapis.com/auth/drive.file',
    extraAuthParams: const {'access_type': 'offline', 'prompt': 'consent'},
    refreshToken: refreshToken,
    onRefreshToken: onRefreshToken,
  );

  static String _randomUrlSafe(int bytes) {
    final r = math.Random.secure();
    return base64Url.encode(List<int>.generate(bytes, (_) => r.nextInt(256))).replaceAll('=', '');
  }

  /// Anmeldung im Browser. [openBrowser] öffnet die Adresse; die Antwort kommt
  /// über einen kleinen Empfänger auf diesem Gerät zurück. [cancel] bricht ab.
  Future<void> signIn(Future<void> Function(Uri url) openBrowser, {Future<void>? cancel}) async {
    final verifier = _randomUrlSafe(48);
    final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final state = _randomUrlSafe(16);
    final url = Uri.parse(authorizeUrl).replace(
      queryParameters: {
        'client_id': clientId,
        'response_type': 'code',
        'redirect_uri': redirectUri,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        'scope': ?scope,
        ...extraAuthParams,
      },
    );

    final servers = <HttpServer>[];
    for (final address in [InternetAddress.loopbackIPv4, InternetAddress.loopbackIPv6]) {
      try {
        servers.add(await HttpServer.bind(address, oauthPort));
      } catch (_) {}
    }
    if (servers.isEmpty) {
      throw CloudAuthException(
        tr(
          'Der Anschluss $oauthPort ist belegt. Bitte Volti neu starten und nochmals versuchen.',
          'Port $oauthPort is in use. Please restart Volti and try again.',
        ),
      );
    }
    final done = Completer<String>();
    for (final server in servers) {
      server.listen((req) async {
        final q = req.uri.queryParameters;
        final ok = q['code'] != null && q['state'] == state;
        req.response.headers.contentType = ContentType.html;
        req.response.write(_page(ok));
        await req.response.close();
        if (done.isCompleted) return;
        if (ok) {
          done.complete(q['code']);
        } else if (q.containsKey('error') || q.containsKey('code')) {
          done.completeError(
            CloudAuthException(
              tr(
                'Die Anmeldung wurde abgebrochen (${q['error'] ?? 'falsche Antwort'}).',
                'Sign-in was cancelled (${q['error'] ?? 'wrong answer'}).',
              ),
            ),
          );
        }
      });
    }
    try {
      await openBrowser(url);
      final code =
          await Future.any([
            done.future,
            if (cancel != null) cancel.then<String>((_) => throw CloudAuthException(tr('Abgebrochen.', 'Cancelled.'))),
          ]).timeout(
            const Duration(minutes: 10),
            onTimeout: () => throw CloudAuthException(tr('Zeit abgelaufen.', 'Timed out.')),
          );
      await _token({
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': redirectUri,
      });
    } finally {
      for (final s in servers) {
        await s.close(force: true);
      }
    }
    if (refreshToken == null) {
      throw CloudAuthException(
        tr('Der Dienst hat keinen dauerhaften Zugang erteilt.', 'The service did not grant lasting access.'),
      );
    }
  }

  static String _page(bool ok) =>
      '<!doctype html><meta charset="utf-8"><title>Volti</title>'
      '<body style="font-family:sans-serif;background:#1f2a28;color:#fff;display:grid;place-items:center;height:90vh">'
      '<div style="text-align:center"><h1 style="color:#5CC8B4">Volti</h1><p>'
      '${ok ? 'Verbunden – du kannst dieses Fenster schliessen.<br>Connected – you can close this window.' : 'Die Anmeldung hat nicht geklappt. / Sign-in failed.'}'
      '</p></div></body>';

  Future<void> _token(Map<String, String> params) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.postUrl(Uri.parse(tokenUrl));
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      final body = {'client_id': clientId, 'client_secret': ?clientSecret, ...params};
      req.write(Uri(queryParameters: body).query);
      final res = await req.close().timeout(const Duration(seconds: 30));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        throw CloudAuthException(
          tr(
            'Anmeldung beim Dienst fehlgeschlagen (${res.statusCode}): $text',
            'Sign-in failed (${res.statusCode}): $text',
          ),
        );
      }
      final j = jsonDecode(text) as Map<String, dynamic>;
      _access = j['access_token'] as String?;
      final expires = (j['expires_in'] as num?)?.toInt() ?? 3600;
      _accessUntil = DateTime.now().add(Duration(seconds: expires - 120));
      final newRefresh = j['refresh_token'] as String?;
      if (newRefresh != null && newRefresh != refreshToken) {
        refreshToken = newRefresh;
        await onRefreshToken?.call(newRefresh);
      }
    } finally {
      client.close(force: true);
    }
  }

  /// Gültiger Zugangsschlüssel (wird bei Bedarf erneuert).
  Future<String> accessToken({bool force = false}) async {
    if (!force && _access != null && DateTime.now().isBefore(_accessUntil)) return _access!;
    final r = refreshToken;
    if (r == null) throw CloudAuthException(tr('Nicht angemeldet.', 'Not signed in.'));
    await _token({'grant_type': 'refresh_token', 'refresh_token': r});
    return _access!;
  }
}
