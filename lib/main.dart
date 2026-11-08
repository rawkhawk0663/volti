import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app/theme.dart';
import 'core/app_settings.dart';
import 'features/library/library_controller.dart';
import 'features/library/library_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  final library = LibraryController(await AppSettings.load());
  library.init(); // liest die Bibliothek im Hintergrund ein
  runApp(VoltiApp(library: library));
}

class VoltiApp extends StatelessWidget {
  const VoltiApp({super.key, required this.library});
  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Volti',
      debugShowCheckedModeBanner: false,
      theme: buildVoltiTheme(Brightness.light),
      darkTheme: buildVoltiTheme(Brightness.dark),
      home: LibraryScreen(library: library),
    );
  }
}
