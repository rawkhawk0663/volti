import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../core/audio/pitch.dart';
import 'tuner.dart';

/// Gitarrensaiten in Normalstimmung (tief nach hoch).
const kGuitarStrings = [40, 45, 50, 55, 59, 64];

/// Fenster „Stimmen“ in der Notenansicht: Stimmgerät (hört über das
/// Mikrofon) und Stimmton (spielt einen Ton zum Anstimmen).
class TunerPanel extends StatefulWidget {
  const TunerPanel({super.key, required this.tuner, required this.onClose});

  final Tuner tuner;
  final VoidCallback onClose;

  @override
  State<TunerPanel> createState() => _TunerPanelState();
}

class _TunerPanelState extends State<TunerPanel> {
  /// Zuletzt gewählter Teil (bleibt, solange die Notenansicht offen ist).
  static bool _pipe = false;
  static int _octave = 4;

  Tuner get tuner => widget.tuner;

  @override
  void initState() {
    super.initState();
    if (!_pipe) tuner.startListening();
  }

  @override
  void dispose() {
    tuner.stopListening();
    tuner.stopNote();
    super.dispose();
  }

  void _choose(bool pipe) {
    if (pipe == _pipe) return;
    setState(() => _pipe = pipe);
    if (pipe) {
      tuner.stopListening();
    } else {
      tuner.stopNote();
      tuner.startListening();
    }
  }

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
          listenable: tuner,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const TuningForkIcon(size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(tr('Stimmen', 'Tuning'), style: theme.textTheme.titleSmall)),
                    IconButton(
                      tooltip: tr('Schliessen', 'Close'),
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: false,
                        icon: const Icon(Icons.mic_none, size: 18),
                        label: Text(tr('Stimmgerät', 'Tuner')),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: const Icon(Icons.volume_up_outlined, size: 18),
                        label: Text(tr('Stimmton', 'Pitch pipe')),
                      ),
                    ],
                    selected: {_pipe},
                    onSelectionChanged: (s) => _choose(s.first),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _pipe ? _buildPipe(context) : _buildTuner(context),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr('Kammerton A = ', 'Concert A = ') + _hz(tuner.a4),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Tiefer', 'Lower'),
                        onPressed: tuner.a4 <= Tuner.minA4 ? null : () => tuner.a4 = tuner.a4 - 1,
                        icon: const Icon(Icons.remove),
                      ),
                      TextButton(onPressed: tuner.a4 == 440 ? null : () => tuner.a4 = 440, child: const Text('440')),
                      IconButton(
                        tooltip: tr('Höher', 'Higher'),
                        onPressed: tuner.a4 >= Tuner.maxA4 ? null : () => tuner.a4 = tuner.a4 + 1,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _hz(double v) => '${v == v.roundToDouble() ? v.round() : v.toStringAsFixed(1)} Hz';

  // ------------------------------------------------------------ Stimmgerät
  Widget _buildTuner(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final english = L10n.isEnglish;
    return ValueListenableBuilder<TunerReading?>(
      valueListenable: tuner.reading,
      builder: (context, r, _) {
        final inTune = r != null && r.cents.abs() <= 3;
        final good = inTune ? const Color(0xFF2E9E5B) : scheme.primary;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 64,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    r == null ? '–' : noteName(r.midi, english: english),
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: r == null ? scheme.outline : (inTune ? good : scheme.onSurface),
                    ),
                  ),
                  if (r != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 10),
                      child: Text('${noteOctave(r.midi)}', style: theme.textTheme.titleMedium),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: CustomPaint(
                painter: _MeterPainter(
                  cents: r?.cents,
                  scale: scheme.outline,
                  needle: inTune ? good : scheme.primary,
                  zone: good.withValues(alpha: 0.18),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              r == null
                  ? (tuner.listening ? tr('Spiel einen Ton …', 'Play a note …') : tr('Mikrofon aus', 'Microphone off'))
                  : '${r.cents >= 0 ? '+' : '−'}${r.cents.abs().round()} ${tr('Cent', 'cents')} · ${r.hz.toStringAsFixed(1)} Hz',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            // Gitarrensaiten: die gerade gespielte leuchtet.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final m in kGuitarStrings)
                  Container(
                    width: 40,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: r?.midi == m ? (inTune ? good : scheme.primary) : scheme.surfaceContainerHighest,
                    ),
                    child: Text(
                      noteName(m, english: english),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: r?.midi == m ? Colors.white : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            if (tuner.micError != null) ...[
              const SizedBox(height: 10),
              Text(tuner.micError!, style: TextStyle(color: scheme.error)),
            ],
            if (tuner.quiet && tuner.micError == null) ...[
              const SizedBox(height: 10),
              Text(
                tr(
                  'Nichts zu hören? Vielleicht darf Volti das Mikrofon nicht benutzen. '
                      'In Windows: Datenschutz → Mikrofon → „Desktop-Apps Zugriff erlauben“.',
                  'Nothing to hear? Volti may not be allowed to use the microphone. '
                      'In Windows: Privacy → Microphone → “Let desktop apps access your microphone”.',
                ),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (Platform.isWindows)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: Tuner.openMicSettings,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(tr('Einstellungen öffnen', 'Open settings')),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------- Stimmton
  Widget _buildPipe(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final english = L10n.isEnglish;

    Widget key(int midi, {String? label, double width = 52}) {
      final on = tuner.playingMidi == midi;
      return SizedBox(
        width: width,
        height: 40,
        child: on
            ? FilledButton(
                style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => tuner.toggleNote(midi),
                child: Text(label ?? noteName(midi, english: english)),
              )
            : OutlinedButton(
                style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => tuner.toggleNote(midi),
                child: Text(label ?? noteName(midi, english: english)),
              ),
      );
    }

    final base = (_octave + 1) * 12; // C der gewählten Oktave
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('Gitarre', 'Guitar'), style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [for (final m in kGuitarStrings) key(m, width: 50)],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Text(tr('Alle Töne', 'All notes'), style: theme.textTheme.labelLarge)),
            IconButton(
              tooltip: tr('Oktave tiefer', 'Octave down'),
              onPressed: _octave <= 2 ? null : () => setState(() => _octave--),
              icon: const Icon(Icons.remove),
            ),
            Text(tr('Oktave $_octave', 'Octave $_octave')),
            IconButton(
              tooltip: tr('Oktave höher', 'Octave up'),
              onPressed: _octave >= 5 ? null : () => setState(() => _octave++),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        for (final row in const [
          [0, 1, 2, 3, 4, 5],
          [6, 7, 8, 9, 10, 11],
        ])
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [for (final i in row) key(base + i, width: 50)],
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            ChoiceChip(
              label: Text(tr('Weich', 'Soft')),
              selected: tuner.sound == PipeSound.soft,
              onSelected: (_) => tuner.sound = PipeSound.soft,
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              label: Text(tr('Gitarre', 'Guitar')),
              selected: tuner.sound == PipeSound.guitar,
              onSelected: (_) => tuner.sound = PipeSound.guitar,
            ),
            const Spacer(),
            if (tuner.playingMidi != null)
              FilledButton.tonalIcon(
                onPressed: tuner.stopNote,
                icon: const Icon(Icons.stop),
                label: Text(tr('Stopp', 'Stop')),
              ),
          ],
        ),
        if (tuner.pipeError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(tuner.pipeError!, style: TextStyle(color: scheme.error)),
          ),
      ],
    );
  }
}

/// Anzeige −50 … +50 Cent mit Nadel; die Mitte ist „gestimmt“.
class _MeterPainter extends CustomPainter {
  _MeterPainter({required this.cents, required this.scale, required this.needle, required this.zone});
  final double? cents;
  final Color scale, needle, zone;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 10.0;
    final w = size.width - 2 * pad;
    double xOf(double c) => pad + (c.clamp(-50, 50) + 50) / 100 * w;
    final mid = size.height / 2;
    // Gestimmt-Bereich (±3 Cent, etwas breiter gezeichnet, damit man ihn sieht)
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(xOf(-5), 2, xOf(5), size.height - 2), const Radius.circular(4)),
      Paint()..color = zone,
    );
    final tick = Paint()
      ..color = scale
      ..strokeWidth = 1.2;
    for (var c = -50; c <= 50; c += 10) {
      final big = c % 50 == 0 || c == 0;
      final h = big ? 14.0 : 7.0;
      canvas.drawLine(Offset(xOf(c.toDouble()), mid - h), Offset(xOf(c.toDouble()), mid + h), tick);
    }
    final c = cents;
    if (c == null) return;
    final x = xOf(c);
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = needle
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      old.cents != cents || old.needle != needle || old.scale != scale || old.zone != zone;
}

/// Symbol einer Stimmgabel.
class TuningForkIcon extends StatelessWidget {
  const TuningForkIcon({super.key, this.size = 24, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _TuningForkPainter(c)),
    );
  }
}

class _TuningForkPainter extends CustomPainter {
  _TuningForkPainter(this.color);
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
    // Zwei lange Zinken, unten rund verbunden, dann der Stiel mit Kugel.
    final fork = Path()
      ..moveTo(9 * s, 2 * s)
      ..lineTo(9 * s, 12 * s)
      ..arcToPoint(Offset(15 * s, 12 * s), radius: Radius.circular(3 * s), clockwise: false)
      ..lineTo(15 * s, 2 * s);
    canvas.drawPath(fork, paint);
    canvas.drawLine(Offset(12 * s, 15 * s), Offset(12 * s, 20 * s), paint);
    canvas.drawCircle(Offset(12 * s, 21 * s), 1.6 * s, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_TuningForkPainter old) => old.color != color;
}
