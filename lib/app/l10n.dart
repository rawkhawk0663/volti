import 'dart:io';

import 'package:flutter/widgets.dart';

/// Sprachen der App. Deutsch ist die Grundsprache (Schweizer Schreibweise).
enum AppLanguage {
  de('Deutsch'),
  en('English');

  const AppLanguage(this.label);

  /// Name der Sprache in ihr selbst (für die Auswahl).
  final String label;

  static AppLanguage? fromCode(String? code) {
    for (final l in values) {
      if (l.name == code) return l;
    }
    return null;
  }

  /// Ohne eigene Wahl: Englisch, wenn das System englisch ist, sonst Deutsch.
  static AppLanguage get system {
    try {
      return Platform.localeName.toLowerCase().startsWith('en') ? AppLanguage.en : AppLanguage.de;
    } catch (_) {
      return AppLanguage.de;
    }
  }

  Locale get locale => this == AppLanguage.de ? const Locale('de', 'CH') : const Locale('en');
}

/// Aktuelle Sprache der App.
///
/// Texte stehen direkt im Code, deutsch und englisch nebeneinander:
/// `tr('Bibliothek', 'Library')`. So bleiben beide Fassungen beisammen.
class L10n {
  L10n._();

  static final language = ValueNotifier<AppLanguage>(AppLanguage.de);

  static bool get isEnglish => language.value == AppLanguage.en;

  /// Sprache wechseln und alles neu aufbauen (auch Texte in Widgets, die
  /// sich sonst nicht neu aufbauen würden).
  static void set(AppLanguage l) {
    if (language.value == l) return;
    language.value = l;
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
  }
}

/// Text in der aktuellen Sprache.
String tr(String de, String en) => L10n.isEnglish ? en : de;
