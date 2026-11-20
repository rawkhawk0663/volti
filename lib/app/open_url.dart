import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// Öffnet eine Internet-Adresse im Standard-Browser.
///
/// Unter Windows über `rundll32` (öffnet kein Konsolenfenster und reicht
/// lange Adressen mit „&“ unverändert weiter), auf Android und iOS über das
/// System (Browser bzw. passende App, z. B. WhatsApp).
Future<void> openUrl(Uri url) async {
  final u = url.toString();
  if (Platform.isAndroid || Platform.isIOS) {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  } else if (Platform.isWindows) {
    await Process.start('rundll32', ['url.dll,FileProtocolHandler', u]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [u]);
  } else {
    await Process.run('xdg-open', [u]);
  }
}
