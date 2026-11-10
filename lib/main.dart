import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app/theme.dart';
import 'app/touch_keyboard.dart';
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
  await pdfrxFlutterInitialize();
  await initFullscreenSupport();
  // Windows: Bildschirmtastatur beim Antippen von Textfeldern (Tablet-Modus).
  TouchKeyboard.install();
  // Voltis eigener Datenordner für Noten, Infos, Anmerkungen und Setlists.
  final support = (await getApplicationSupportDirectory()).path;
  final settings = await AppSettings.load();
  final library = LibraryController(settings, root: p.join(support, 'Bibliothek'));
  final sync = SyncController(library: library, settings: settings, deviceDataDir: support);
  final tools = ToolController(settings: settings, store: ToolStore(library.root));
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
  });
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
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: tools.themeMode,
        builder: (context, mode, home) => MaterialApp(
          title: 'Volti',
          debugShowCheckedModeBanner: false,
          theme: buildVoltiTheme(Brightness.light),
          darkTheme: buildVoltiTheme(Brightness.dark),
          themeMode: mode,
          home: home,
        ),
        child: LibraryScreen(library: library, sync: sync),
      ),
    );
  }
}
