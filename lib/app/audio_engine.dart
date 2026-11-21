import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// Gemeinsame Audio-Technik (SoLoud) für Aufnahme, Metronom und Stimmton.
///
/// Sie läuft nur, solange jemand sie braucht ([use] … [done]). Ist niemand
/// mehr angemeldet, wird sie nach [idle] schlafen gelegt: Eine laufende
/// Audio-Technik rechnet ständig (auch Stille), das kostet auf dem Tablet
/// Prozessor und Akku. Wer sie wieder braucht, weckt sie mit [use] (dauert
/// einen Augenblick).
class AudioEngine {
  AudioEngine._();

  static const idle = Duration(seconds: 30);

  static final _users = <Object>{};
  static Timer? _sleep;
  static Future<void>? _starting;

  /// Anmelden und die Audio-Technik bereitstellen.
  static Future<SoLoud> use(Object who) async {
    _users.add(who);
    _sleep?.cancel();
    _sleep = null;
    final s = SoLoud.instance;
    if (!s.isInitialized) {
      _starting ??= s.init(bufferSize: 512).whenComplete(() {
        _starting = null;
      });
      await _starting;
    }
    return s;
  }

  /// Abmelden. Vorher alle eigenen Klänge freigeben: Beim Schlafenlegen
  /// werden alle geladenen Klänge verworfen.
  static void done(Object who) {
    if (!_users.remove(who)) return;
    if (_users.isNotEmpty) return;
    _sleep?.cancel();
    _sleep = Timer(idle, () {
      _sleep = null;
      if (_users.isNotEmpty || _starting != null) return;
      final s = SoLoud.instance;
      if (s.isInitialized) {
        try {
          s.deinit();
        } catch (e) {
          debugPrint('Audio-Technik: $e');
        }
      }
    });
  }

  @visibleForTesting
  static bool isUsedBy(Object who) => _users.contains(who);
}
