import 'package:flutter/material.dart';

import 'theme.dart';

/// Knopf mit Farbverlauf (Hauptaktion). [secondary]: ruhiger Knopf in
/// Kartenfarbe mit Rand, für Nebenaktionen neben einem Hauptknopf.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.colors,
    this.secondary = false,
    this.compact = false,
  });

  final String label;

  /// Symbol links (z. B. `Icon(Icons.add)` oder eine Ladeanzeige).
  final Widget? icon;
  final VoidCallback? onPressed;
  final List<Color>? colors;
  final bool secondary;

  /// Kleiner, z. B. in einer Leiste oben.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final v = context.volti;
    final scheme = Theme.of(context).colorScheme;
    // Auf dem Verlauf immer weiss (Wunsch des Besitzers), auch im Dunkelmodus.
    final onColor = secondary ? scheme.onSurface : Colors.white;
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: secondary ? null : LinearGradient(colors: colors ?? v.brand),
          color: secondary ? v.cardHigh : null,
          border: secondary ? Border.all(color: v.line) : null,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onPressed,
            child: Padding(
              padding: compact
                  ? const EdgeInsets.symmetric(horizontal: 16, vertical: 9)
                  : const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: IconTheme.merge(
                data: IconThemeData(size: 20, color: onColor),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[icon!, const SizedBox(width: 8)],
                    Text(
                      label,
                      style: TextStyle(color: onColor, fontWeight: FontWeight.w600, fontSize: compact ? 14 : 15),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Schwebender Knopf unten rechts mit Verlauf und weichem Leuchten.
class GradientFab extends StatelessWidget {
  const GradientFab({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.secondary = false,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final v = context.volti;
    final glow = secondary ? Colors.black.withValues(alpha: 0.18) : v.brand.last.withValues(alpha: 0.35);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: [BoxShadow(color: glow, blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: GradientButton(label: label, icon: icon, onPressed: onPressed, secondary: secondary),
    );
  }
}

/// Runder Symbol-Knopf mit Verlauf (z. B. in schwebenden Leisten).
class GradientIconButton extends StatelessWidget {
  const GradientIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 40,
  });

  final IconData icon;
  final double size;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final v = context.volti;
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onPressed == null ? 0.35 : 1,
        child: Material(
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(gradient: LinearGradient(colors: v.brand)),
            child: InkWell(
              onTap: onPressed,
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(icon, size: size / 2, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bildmarke von Volti (die zwei Blätter) im Markenverlauf.
class VoltiMark extends StatelessWidget {
  const VoltiMark({super.key, this.height = 34});
  final double height;

  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/brand/volti_mark.png', height: height, filterQuality: FilterQuality.medium);
}
