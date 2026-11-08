import 'dart:io';

import 'package:volti/core/app_settings.dart';
import 'package:volti/core/ink/drawing_preset.dart';
import 'package:volti/features/viewer/tool_controller.dart';

/// Werkzeug-Steuerung für Tests, mit Einstellungen in einem Testordner.
Future<ToolController> makeTools(Directory dir) async {
  final settings = await AppSettings.loadFrom(Directory('${dir.path}/settings'));
  return ToolController(settings: settings, store: PresetStore('${dir.path}/bibliothek'));
}
