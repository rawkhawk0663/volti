import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app/theme.dart';
import 'features/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  runApp(const VoltiApp());
}

class VoltiApp extends StatelessWidget {
  const VoltiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Volti',
      debugShowCheckedModeBanner: false,
      theme: buildVoltiTheme(Brightness.light),
      darkTheme: buildVoltiTheme(Brightness.dark),
      home: const HomeScreen(),
    );
  }
}
