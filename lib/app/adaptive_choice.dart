import 'package:flutter/material.dart';

/// Eine Möglichkeit in [AdaptiveChoice].
class ChoiceOption<T> {
  const ChoiceOption(this.value, this.label, {this.icon});
  final T value;
  final String label;
  final IconData? icon;
}

/// Auswahl aus wenigen Möglichkeiten: mit genug Platz nebeneinander
/// (`SegmentedButton`), auf schmalen Bildschirmen untereinander als Liste.
/// Sonst würden die Wörter auf dem Handy Buchstabe für Buchstabe umbrechen.
class AdaptiveChoice<T> extends StatelessWidget {
  const AdaptiveChoice({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.minWidth,
  });

  final List<ChoiceOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Ab dieser Breite nebeneinander (sonst pro Möglichkeit 150 Punkte).
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= (minWidth ?? options.length * 150)) {
          return SegmentedButton<T>(
            segments: [
              for (final o in options)
                ButtonSegment(value: o.value, icon: o.icon == null ? null : Icon(o.icon), label: Text(o.label)),
            ],
            selected: {selected},
            onSelectionChanged: (s) => onChanged(s.first),
          );
        }
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return Material(
          type: MaterialType.transparency,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, o) in options.indexed) ...[
                if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                _Row(option: o, selected: o.value == selected, onTap: () => onChanged(o.value)),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Row<T> extends StatelessWidget {
  const _Row({required this.option, required this.selected, required this.onTap});
  final ChoiceOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    return Material(
      color: selected ? scheme.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              if (option.icon != null) ...[Icon(option.icon, size: 20, color: fg), const SizedBox(width: 12)],
              Expanded(
                child: Text(option.label, style: TextStyle(color: fg, fontWeight: selected ? FontWeight.w600 : null)),
              ),
              if (selected) Icon(Icons.check, size: 20, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}
