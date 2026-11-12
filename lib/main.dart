import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app/error_log.dart';
import 'app/l10n.dart';
import 'app/theme.dart';
import 'app/touch_keyboard.dart';
import 'app/updater.dart';
import 'app/window_buttons.dart';
import 'core/app_settings.dart';
import 'core/ink/custom_stamps.dart';
import 'core/ink/tool_settings.dart';
import 'features/library/library_controller.dart';
import 'features/library/library_screen.dart';
import 'features/library/sync_controller.dart';
import 'features/viewer/custom_stamp_registry.dart';
import 'features/viewer/fullscreen.dart';
import 'features/viewer/tool_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Voltis eigener Datenordner für Noten, Infos, Anmerkungen und Setlists.
  final support = (await getApplicationSupportDirectory()).path;
  // Fehler in eine Datei schreiben (⚙ → Fehlerprotokoll).
  ErrorLog.install(support);
  _registerFontLicenses();
  await pdfrxFlutterInitialize();
  await initFullscreenSupport();
  // Windows: eigene Fensterknöpfe statt der Titelleiste (cleaner Look).
  await hideNativeTitleBar();
  // Windows: Bildschirmtastatur beim Antippen von Textfeldern (Tablet-Modus).
  TouchKeyboard.install();
  final settings = await AppSettings.load();
  final library = LibraryController(settings, root: p.join(support, 'Bibliothek'));
  final sync = SyncController(library: library, settings: settings, deviceDataDir: support);
  final tools = ToolController(settings: settings, store: ToolStore(library.root));
  // Sprache der App (⚙ → Darstellung).
  L10n.language.value = tools.language;
  // Geänderte Stift-Vorlagen abgleichen; neue vom anderen Gerät übernehmen.
  tools.onSettingsChanged = sync.scheduleSoon;
  // Eigene Stempel (Bilder in Bibliothek/.volti/stamps), ebenfalls abgeglichen.
  final stamps = CustomStamps.instance = CustomStamps(CustomStampStore(library.root));
  stamps.onLocalChange = sync.scheduleSoon;
  sync.afterDownload = () async {
    await tools.load();
    await stamps.load();
  };
  // Bibliothek im Hintergrund einlesen, danach abgleichen.
  library.init().then((_) async {
    await tools.load();
    await stamps.load();
    sync.start();
    // Einmal pro Woche alles sichern.
    library.autoBackup.start();
  });
  // Nach einem Update: alte, beiseitegeschobene Programmdateien wegräumen.
  Future<void>.delayed(const Duration(seconds: 5), Updater.cleanUp);
  runApp(VoltiApp(library: library, sync: sync, tools: tools));
}

class VoltiApp extends StatelessWidget {
  const VoltiApp({super.key, required this.library, required this.sync, required this.tools});
  final LibraryController library;
  final SyncController sync;
  final ToolController tools;

  @override
  Widget build(BuildContext context) {
    return ToolScope(
      tools: tools,
      child: ListenableBuilder(
        listenable: Listenable.merge([tools.themeMode, L10n.language]),
        builder: (context, home) => MaterialApp(
          title: 'Volti',
          debugShowCheckedModeBanner: false,
          theme: buildVoltiTheme(Brightness.light),
          darkTheme: buildVoltiTheme(Brightness.dark),
          themeMode: tools.themeMode.value,
          // Eingebaute Texte (Kopieren/Einfügen, Lizenzen …) in der Sprache der App,
          // Deutsch in Schweizer Schreibweise.
          locale: L10n.language.value.locale,
          supportedLocales: const [Locale('de', 'CH'), Locale('de'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: home,
        ),
        child: LibraryScreen(library: library, sync: sync),
      ),
    );
  }
}

/// Lizenzen der Schriften, die Volti mitbringt (⚙ → Lizenzen).
void _registerFontLicenses() {
  const fonts = {
    'Bravura': 'OFL-Bravura.txt',
    'Noto Serif': 'OFL-NotoSerif.txt',
    'Roboto': 'OFL-Roboto.txt',
    'Roboto Mono': 'OFL-RobotoMono.txt',
  };
  LicenseRegistry.addLicense(() async* {
    for (final e in fonts.entries) {
      try {
        yield LicenseEntryWithLineBreaks([e.key], await rootBundle.loadString('assets/fonts/${e.value}'));
      } catch (_) {}
    }
  });
}
