import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'metronome.dart';

/// Kleines Fenster mit dem Metronom (in der Notenansicht).
///
/// Das Tempo kommt aus den Infos des Stücks (falls eingetragen) und lässt
/// sich hier jederzeit anpassen. [onRemember] speichert das eingestellte
/// Tempo beim Stück (null = nicht möglich).
class MetronomePanel extends StatelessWidget {
  const MetronomePanel({
    super.key,
    required this.metronome,
    required this.onClose,
    this.onRemember,
    this.songTempo,
    this.songTitle,
  });

  final Metronome metronome;
  final VoidCallback onClose;
  final VoidCallback? onRemember;
  final int? songTempo;
  final String? songTitle;

  static const _meters = [(2, '2/4'), (3, '3/4'), (4, '4/4'), (6, '6/8')];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 380,
        child: ListenableBuilder(
          listenable: metronome,
          builder: (context, _) {
            final m = metronome;
            Widget step(String label, int delta) => SizedBox(
              width: 40,
              child: TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => m.bpm = m.bpm + delta,
                child: Text(label),
              ),
            );
            final differs = songTempo != m.bpm;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const MetronomeIcon(size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Metronom', style: theme.textTheme.titleSmall)),
                      IconButton(tooltip: 'Schliessen', onPressed: onClose, icon: const Icon(Icons.close)),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${m.bpm}', style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('BPM', style: theme.textTheme.labelLarge),
                      ),
                      const Spacer(),
                      // Schläge des Takts; der aktuelle leuchtet.
                      ValueListenableBuilder<int>(
                        valueListenable: m.beat,
                        builder: (context, b, _) => Row(
                          children: [
                            for (var i = 0; i < math.min(m.beats, 12); i++)
                              Container(
                                width: i == 0 ? 14 : 11,
                                height: i == 0 ? 14 : 11,
                                margin: const EdgeInsets.only(left: 5, bottom: 10),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: b == i ? scheme.primary : scheme.outlineVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                  if (songTempo != null && songTitle != null)
                    Text(
                      differs ? 'Im Stück eingetragen: $songTempo BPM' : 'Tempo aus „$songTitle“',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  Row(
                    children: [
                      step('−5', -5),
                      step('−1', -1),
                      Expanded(
                        child: Slider(
                          min: Metronome.minBpm.toDouble(),
                          max: Metronome.maxBpm.toDouble(),
                          value: m.bpm.toDouble(),
                          onChanged: (v) => m.bpm = v.round(),
                        ),
                      ),
                      step('+1', 1),
                      step('+5', 5),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (b, label) in _meters)
                        ChoiceChip(label: Text(label), selected: m.beats == b, onSelected: (_) => m.beats = b),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in ClickSound.values)
                        ChoiceChip(label: Text(s.label), selected: m.sound == s, onSelected: (_) => m.sound = s),
                    ],
                  ),
                  if (m.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(m.error!, style: TextStyle(color: scheme.error)),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: m.tap,
                        child: const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('Tippen')),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: m.toggle,
                          icon: Icon(m.running ? Icons.stop : Icons.play_arrow),
                          label: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(m.running ? 'Stopp' : 'Start'),
                          ),
                        ),
                      ),
                      if (onRemember != null && differs) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Tempo beim Stück speichern',
                          onPressed: onRemember,
                          icon: const Icon(Icons.save_outlined),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Symbol eines Metronoms (Pyramide mit Pendel).
class MetronomeIcon extends StatelessWidget {
  const MetronomeIcon({super.key, this.size = 24, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MetronomeIconPainter(c)),
    );
  }
}

class _MetronomeIconPainter extends CustomPainter {
  _MetronomeIconPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final body = Path()
      ..moveTo(9 * s, 3 * s)
      ..lineTo(15 * s, 3 * s)
      ..lineTo(19.5 * s, 21 * s)
      ..lineTo(4.5 * s, 21 * s)
      ..close();
    canvas.drawPath(body, paint);
    canvas.drawLine(Offset(6 * s, 16 * s), Offset(18 * s, 16 * s), paint);
    canvas.drawLine(Offset(12 * s, 16 * s), Offset(17 * s, 6 * s), paint);
  }

  @override
  bool shouldRepaint(_MetronomeIconPainter old) => old.color != color;
}
