import 'package:flutter/material.dart';

import 'visuals.dart';

/// Knöpfe zum Anlegen und Hinzufügen stehen in Volti immer schwebend unten
/// rechts (wie „Importieren“ in der Bibliothek). Mehrere stehen nebeneinander,
/// die Hauptaktion (Verlauf) ganz rechts.
///
/// Für Seiten ohne eigenes `Scaffold`: [child] füllt die Fläche, die Knöpfe
/// liegen darüber. Listen darunter brauchen unten etwa 96 Punkte Platz.
class FloatingActions extends StatelessWidget {
  const FloatingActions({super.key, required this.child, required this.actions});

  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: child),
      if (actions.isNotEmpty)
        Positioned(
          right: 16,
          bottom: 16,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 12), actions[i]],
            ],
          ),
        ),
    ],
  );
}

/// Ein schwebender Knopf mit Symbol und Text im Markenverlauf.
/// [secondary]: ruhiger Nebenknopf (steht links vom Hauptknopf).
Widget floatingAction({
  required IconData icon,
  required String label,
  required VoidCallback? onPressed,
  bool secondary = false,
}) => GradientFab(icon: Icon(icon), label: label, onPressed: onPressed, secondary: secondary);
