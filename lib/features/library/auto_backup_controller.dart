import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/error_log.dart';
import '../../core/app_settings.dart';
import '../../core/library/auto_backup.dart';

/// Wöchentliche automatische Sicherung (Einstellung pro Gerät, Standard: an).
class AutoBackupController extends ChangeNotifier {
  AutoBackupController({required this.settings, required this.root});
  final AppSettings settings;
  final String root;

  Timer? _timer;
  bool _running = false;
  bool get running => _running;

  /// Fehler der letzten automatischen Sicherung (null = ging).
  String? lastError;

  bool get enabled => settings.flag('autoBackup', orElse: true);

  /// Selbst gewählter Ordner (null = Standard: Dokumente\Volti-Sicherungen).
  String? get customFolder => settings.text('autoBackupDir');

  Future<String> folder() async {
    final custom = customFolder;
    if (custom != null) return custom;
    try {
      return p.join((await getApplicationDocumentsDirectory()).path, 'Volti-Sicherungen');
    } catch (_) {
      // Kein Dokumente-Ordner: in Voltis Datenordner (neben der Bibliothek).
      return p.join(p.dirname(root), 'Sicherungen');
    }
  }

  DateTime? get last => DateTime.tryParse(settings.text('autoBackupLast') ?? '');

  /// Kurz nach dem Start und danach alle paar Stunden prüfen, ob eine
  /// Sicherung fällig ist.
  void start() {
    _timer?.cancel();
    Timer(const Duration(minutes: 1), runIfDue);
    _timer = Timer.periodic(const Duration(hours: 6), (_) => runIfDue());
  }

  Future<void> setEnabled(bool on) async {
    await settings.setFlag('autoBackup', on);
    notifyListeners();
    if (on) unawaited(runIfDue());
  }

  Future<void> setFolder(String dir) async {
    await settings.setText('autoBackupDir', dir);
    notifyListeners();
  }

  Future<void> runIfDue() async {
    if (!enabled || !AutoBackup.isDue(last, DateTime.now())) return;
    await runNow();
  }

  Future<void> runNow() async {
    if (_running) return;
    _running = true;
    notifyListeners();
    try {
      await AutoBackup.run(root, await folder());
      await settings.setText('autoBackupLast', DateTime.now().toIso8601String());
      lastError = null;
    } catch (e, s) {
      lastError = '$e';
      ErrorLog.record(e, s, where: 'Automatische Sicherung');
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
