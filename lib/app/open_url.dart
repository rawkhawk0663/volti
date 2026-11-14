import 'dart:io';

/// Öffnet eine Internet-Adresse im Standard-Browser.
///
/// Unter Windows über `rundll32` (öffnet kein Konsolenfenster und reicht
/// lange Adressen mit „&“ unverändert weiter).
Future<void> openUrl(Uri url) async {
  final u = url.toString();
  if (Platform.isWindows) {
    await Process.start('rundll32', ['url.dll,FileProtocolHandler', u]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [u]);
  } else {
    await Process.run('xdg-open', [u]);
  }
}
