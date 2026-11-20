import 'dart:convert';

import 'package:flutter/services.dart';

import '../../app/l10n.dart';

/// Was man beim Schreiben einer Tabulatur mit der Tastatur tun kann.
/// Die Bundzahlen (Ziffern 0–9, obere Reihe oder Ziffernblock) sind fest.
enum TabAction {
  left,
  right,
  up,
  down,
  whole,
  half,
  quarter,
  eighth,
  sixteenth,
  thirtySecond,
  shorter,
  longer,
  dot,
  rest,
  bar,
  clearNote,
  deleteBeat,
  insertBeat,
  finish;

  String get label => switch (this) {
    left => tr('Vorheriger Schlag', 'Previous beat'),
    right => tr('Nächster Schlag', 'Next beat'),
    up => tr('Saite höher (Linie darüber)', 'String up (line above)'),
    down => tr('Saite tiefer (Linie darunter)', 'String down (line below)'),
    whole => tr('Ganze Note', 'Whole note'),
    half => tr('Halbe Note', 'Half note'),
    quarter => tr('Viertelnote', 'Quarter note'),
    eighth => tr('Achtelnote', 'Eighth note'),
    sixteenth => tr('Sechzehntelnote', 'Sixteenth note'),
    thirtySecond => tr('Zweiunddreissigstelnote', 'Thirty-second note'),
    shorter => tr('Notenwert kürzer', 'Shorter note value'),
    longer => tr('Notenwert länger', 'Longer note value'),
    dot => tr('Punktiert ein/aus', 'Dotted on/off'),
    rest => tr('Pause', 'Rest'),
    bar => tr('Taktstrich', 'Bar line'),
    clearNote => tr('Bundzahl löschen', 'Delete fret number'),
    deleteBeat => tr('Ganzen Schlag löschen', 'Delete whole beat'),
    insertBeat => tr('Schlag einfügen', 'Insert beat'),
    finish => tr('Fertig (Schreiben beenden)', 'Done (stop writing)'),
  };

  /// Notenwert, den diese Taste setzt (sonst null).
  int? get noteValue => switch (this) {
    whole => 1,
    half => 2,
    quarter => 4,
    eighth => 8,
    sixteenth => 16,
    thirtySecond => 32,
    _ => null,
  };
}

/// Eine Taste mit Zusatztasten (Strg, Umschalt, Alt).
class KeyBinding {
  const KeyBinding(this.key, {this.ctrl = false, this.shift = false, this.alt = false});

  final LogicalKeyboardKey key;
  final bool ctrl, shift, alt;

  bool matches(LogicalKeyboardKey k, {required bool ctrl, required bool shift, required bool alt}) =>
      k == key && ctrl == this.ctrl && shift == this.shift && alt == this.alt;

  bool sameAs(KeyBinding o) => o.key == key && o.ctrl == ctrl && o.shift == shift && o.alt == alt;

  /// Für die Anzeige, z. B. „Strg+K“ oder „←“.
  String get label {
    final name = switch (key) {
      LogicalKeyboardKey.arrowLeft => '←',
      LogicalKeyboardKey.arrowRight => '→',
      LogicalKeyboardKey.arrowUp => '↑',
      LogicalKeyboardKey.arrowDown => '↓',
      LogicalKeyboardKey.escape => 'Esc',
      LogicalKeyboardKey.backspace => tr('Rücktaste', 'Backspace'),
      LogicalKeyboardKey.delete => tr('Entf', 'Del'),
      LogicalKeyboardKey.insert => tr('Einfg', 'Ins'),
      LogicalKeyboardKey.enter => 'Enter',
      LogicalKeyboardKey.space => tr('Leertaste', 'Space'),
      LogicalKeyboardKey.tab => 'Tab',
      _ => key.keyLabel.length == 1 ? key.keyLabel.toUpperCase() : key.keyLabel,
    };
    return [if (ctrl) tr('Strg', 'Ctrl'), if (alt) 'Alt', if (shift) tr('Umschalt', 'Shift'), name].join('+');
  }

  Map<String, dynamic> toJson() => {'k': key.keyId, if (ctrl) 'c': true, if (shift) 's': true, if (alt) 'a': true};

  static KeyBinding? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['k'];
    if (id is! int) return null;
    return KeyBinding(
      LogicalKeyboardKey.findKeyByKeyId(id) ?? LogicalKeyboardKey(id),
      ctrl: j['c'] == true,
      shift: j['s'] == true,
      alt: j['a'] == true,
    );
  }
}

/// Tastenbelegung für das Schreiben von Tabulaturen (pro Gerät gemerkt).
///
/// Die Standardtasten brauchen keinen Ziffernblock: Notenwerte liegen auf
/// Buchstaben (G = ganze, H = halbe, V = Viertel, A = Achtel, S = Sechzehntel,
/// Z = Zweiunddreissigstel), Bundzahlen auf der Ziffern-Reihe oben.
class TabKeymap {
  TabKeymap(Map<TabAction, KeyBinding> bindings) : _b = Map.unmodifiable(bindings);

  final Map<TabAction, KeyBinding> _b;

  static final defaults = TabKeymap({
    TabAction.left: const KeyBinding(LogicalKeyboardKey.arrowLeft),
    TabAction.right: const KeyBinding(LogicalKeyboardKey.arrowRight),
    TabAction.up: const KeyBinding(LogicalKeyboardKey.arrowUp),
    TabAction.down: const KeyBinding(LogicalKeyboardKey.arrowDown),
    TabAction.whole: const KeyBinding(LogicalKeyboardKey.keyG),
    TabAction.half: const KeyBinding(LogicalKeyboardKey.keyH),
    TabAction.quarter: const KeyBinding(LogicalKeyboardKey.keyV),
    TabAction.eighth: const KeyBinding(LogicalKeyboardKey.keyA),
    TabAction.sixteenth: const KeyBinding(LogicalKeyboardKey.keyS),
    TabAction.thirtySecond: const KeyBinding(LogicalKeyboardKey.keyZ),
    TabAction.shorter: const KeyBinding(LogicalKeyboardKey.keyK),
    TabAction.longer: const KeyBinding(LogicalKeyboardKey.keyL),
    TabAction.dot: const KeyBinding(LogicalKeyboardKey.period),
    TabAction.rest: const KeyBinding(LogicalKeyboardKey.keyP),
    TabAction.bar: const KeyBinding(LogicalKeyboardKey.keyT),
    TabAction.clearNote: const KeyBinding(LogicalKeyboardKey.backspace),
    TabAction.deleteBeat: const KeyBinding(LogicalKeyboardKey.delete),
    TabAction.insertBeat: const KeyBinding(LogicalKeyboardKey.keyN),
    TabAction.finish: const KeyBinding(LogicalKeyboardKey.escape),
  });

  KeyBinding? operator [](TabAction a) => _b[a];

  TabAction? actionFor(LogicalKeyboardKey k, {required bool ctrl, required bool shift, required bool alt}) {
    for (final e in _b.entries) {
      if (e.value.matches(k, ctrl: ctrl, shift: shift, alt: alt)) return e.key;
    }
    return null;
  }

  /// Neue Taste für [action]. Gehört sie schon einer anderen Aktion, tauschen
  /// die beiden ihre Tasten (so geht nie eine Belegung verloren).
  ({TabKeymap map, TabAction? swapped}) withBinding(TabAction action, KeyBinding k) {
    final next = Map<TabAction, KeyBinding>.of(_b);
    TabAction? swapped;
    for (final e in _b.entries) {
      if (e.key != action && e.value.sameAs(k)) {
        swapped = e.key;
        final old = _b[action];
        if (old != null) {
          next[e.key] = old;
        } else {
          next.remove(e.key);
        }
      }
    }
    next[action] = k;
    return (map: TabKeymap(next), swapped: swapped);
  }

  String toJson() => jsonEncode({for (final e in _b.entries) e.key.name: e.value.toJson()});

  /// Gespeicherte Belegung; was fehlt, kommt von den Standardtasten.
  static TabKeymap fromJson(String? s) {
    if (s == null || s.isEmpty) return defaults;
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      final map = Map<TabAction, KeyBinding>.of(defaults._b);
      for (final a in TabAction.values) {
        final k = KeyBinding.fromJson(j[a.name]);
        if (k != null) map[a] = k;
      }
      return TabKeymap(map);
    } catch (_) {
      return defaults;
    }
  }
}

/// Ziffer einer Taste (obere Reihe oder Ziffernblock), sonst null.
int? digitOf(LogicalKeyboardKey k) {
  const top = [
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  const pad = [
    LogicalKeyboardKey.numpad0,
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];
  final i = top.indexOf(k);
  if (i >= 0) return i;
  final j = pad.indexOf(k);
  return j >= 0 ? j : null;
}

/// Reine Zusatztasten (zählen beim Festlegen nicht als Taste).
bool isModifierKey(LogicalKeyboardKey k) => const [
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.fn,
  LogicalKeyboardKey.altGraph,
].contains(k);
