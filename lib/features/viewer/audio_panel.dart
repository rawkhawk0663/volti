import 'package:flutter/material.dart';

import 'score_audio_player.dart';
import '../../app/l10n.dart';
import '../../app/visuals.dart';

/// Kleines Fenster mit der Aufnahme des Stücks (in der Notenansicht).
///
/// Ohne Aufnahme bietet es an, eine Datei zuzuordnen ([onPick]). Mit Aufnahme:
/// Abspielen, Stelle wählen, Tempo und Tonhöhe, Schleife A–B.
class AudioPanel extends StatelessWidget {
  const AudioPanel({
    super.key,
    required this.player,
    required this.onClose,
    required this.onPick,
    required this.onRemove,
    this.fileName,
    this.songTitle,
  });

  final ScoreAudioPlayer player;
  final VoidCallback onClose;

  /// Datei wählen (null = für dieses Stück nicht möglich).
  final VoidCallback? onPick;
  final VoidCallback? onRemove;

  /// Name der zugeordneten Datei (zur Anzeige).
  final String? fileName;
  final String? songTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 380,
        child: ListenableBuilder(
          listenable: player,
          builder: (context, _) {
            final a = player;
            final has = a.path != null;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.headphones_outlined, size: 20, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(tr('Aufnahme', 'Recording'), style: theme.textTheme.titleSmall)),
                      if (has && (onPick != null || onRemove != null))
                        PopupMenuButton<String>(
                          tooltip: tr('Mehr', 'More'),
                          icon: const Icon(Icons.more_vert),
                          onSelected: (v) => v == 'pick' ? onPick?.call() : onRemove?.call(),
                          itemBuilder: (c) => [
                            if (onPick != null)
                              PopupMenuItem(
                                value: 'pick',
                                child: ListTile(
                                  leading: const Icon(Icons.swap_horiz),
                                  title: Text(tr('Andere Datei wählen …', 'Choose another file …')),
                                ),
                              ),
                            if (onRemove != null)
                              PopupMenuItem(
                                value: 'remove',
                                child: ListTile(
                                  leading: const Icon(Icons.delete_outline),
                                  title: Text(tr('Aufnahme entfernen', 'Remove recording')),
                                ),
                              ),
                          ],
                        ),
                      IconButton(tooltip: tr('Schliessen', 'Close'), onPressed: onClose, icon: const Icon(Icons.close)),
                    ],
                  ),
                  if (!has) ..._empty(context, muted) else ..._player(context, theme, muted),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _empty(BuildContext context, TextStyle? muted) => [
    Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 12),
      child: Text(
        tr(
          'Ordne diesem Stück eine Aufnahme zu (MP3, M4A, WAV, OGG oder FLAC). Sie wird beim Öffnen des Stücks '
              'immer mitgeladen und mit deinen anderen Geräten abgeglichen. Du kannst die Datei auch auf die '
              'Notenseite ziehen.',
          'Attach a recording to this piece (MP3, M4A, WAV, OGG or FLAC). It is loaded whenever you open the '
              'piece and synced with your other devices. You can also drag the file onto the page.',
        ),
        style: muted,
      ),
    ),
    Align(
      alignment: Alignment.centerLeft,
      child: GradientButton(
        label: tr('Audio-Datei wählen …', 'Choose audio file …'),
        icon: const Icon(Icons.audio_file_outlined, color: Colors.white, size: 18),
        onPressed: onPick,
      ),
    ),
  ];

  List<Widget> _player(BuildContext context, ThemeData theme, TextStyle? muted) {
    final a = player;
    final scheme = theme.colorScheme;
    final len = a.length;
    Widget small(String label, VoidCallback? onTap, {String? tip}) => SizedBox(
      width: 44,
      child: Tooltip(
        message: tip ?? '',
        child: TextButton(
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          onPressed: onTap,
          child: Text(label),
        ),
      ),
    );
    final speedPct = (a.speed * 100).round();
    final st = a.semitones;
    return [
      if (fileName != null)
        Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 2),
          child: Text(fileName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
        ),
      if (a.error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6, right: 8),
          child: Text(a.error!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
        ),
      if (a.loading) const Padding(padding: EdgeInsets.fromLTRB(0, 12, 8, 12), child: LinearProgressIndicator()),
      if (a.ready) ...[
        // Stelle: Schieber mit Zeit; die Schleife ist darunter markiert.
        ValueListenableBuilder<Duration>(
          valueListenable: a.position,
          builder: (context, pos, _) {
            final max = len.inMilliseconds.toDouble().clamp(1.0, double.infinity);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(overlayShape: SliderComponentShape.noOverlay),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 12, 0),
                    child: Slider(
                      min: 0,
                      max: max,
                      value: pos.inMilliseconds.toDouble().clamp(0, max),
                      onChanged: (v) => a.seek(Duration(milliseconds: v.round())),
                    ),
                  ),
                ),
                if (a.loopA != null || a.loopB != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                    child: _LoopBar(length: len, a: a.loopA, b: a.loopB, color: scheme.tertiary),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                  child: Row(
                    children: [
                      Text(formatTime(pos), style: muted),
                      const Spacer(),
                      Text(formatTime(len), style: muted),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: a.looping ? tr('Zum Anfang der Schleife', 'To loop start') : tr('Zum Anfang', 'To the start'),
              onPressed: a.rewind,
              icon: const Icon(Icons.skip_previous),
            ),
            IconButton(
              tooltip: tr('5 Sekunden zurück', 'Back 5 seconds'),
              onPressed: () => a.skip(const Duration(seconds: -5)),
              icon: const Icon(Icons.replay_5),
            ),
            const SizedBox(width: 8),
            GradientIconButton(
              size: 56,
              icon: a.playing ? Icons.pause : Icons.play_arrow,
              tooltip: a.playing ? tr('Pause', 'Pause') : tr('Abspielen', 'Play'),
              onPressed: a.toggle,
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: tr('5 Sekunden vor', 'Forward 5 seconds'),
              onPressed: () => a.skip(const Duration(seconds: 5)),
              icon: const Icon(Icons.forward_5),
            ),
            IconButton(
              tooltip: tr('Schleife A–B: zuerst Anfang, dann Ende setzen', 'Loop A–B: set the start, then the end'),
              isSelected: a.looping,
              onPressed: () {
                if (a.looping) {
                  a.clearLoop();
                } else if (a.loopA == null) {
                  a.setLoopA();
                } else {
                  a.setLoopB();
                }
              },
              icon: Text(
                a.looping ? 'A–B' : (a.loopA == null ? 'A' : 'B'),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: a.looping || a.loopA != null ? scheme.primary : null,
                ),
              ),
            ),
          ],
        ),
        if (a.loopA != null && !a.looping)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              tr(
                'Anfang ${formatTime(a.loopA!)} gesetzt. Tippe am Ende der Stelle nochmals auf „B“.',
                'Start ${formatTime(a.loopA!)} set. Tap “B” again at the end of the passage.',
              ),
              textAlign: TextAlign.center,
              style: muted,
            ),
          ),
        const SizedBox(height: 8),
        // Tempo und Tonhöhe
        Row(
          children: [
            SizedBox(width: 74, child: Text(tr('Tempo', 'Speed'), style: theme.textTheme.bodyMedium)),
            small('−5', () => a.setSpeed(a.speed - 0.05)),
            Expanded(
              child: Center(
                child: Text(
                  '$speedPct %',
                  style: theme.textTheme.titleMedium?.copyWith(color: speedPct != 100 ? scheme.primary : null),
                ),
              ),
            ),
            small('+5', () => a.setSpeed(a.speed + 0.05)),
            small('↺', speedPct == 100 ? null : () => a.setSpeed(1), tip: tr('Originaltempo', 'Original speed')),
          ],
        ),
        Row(
          children: [
            SizedBox(width: 74, child: Text(tr('Tonhöhe', 'Pitch'), style: theme.textTheme.bodyMedium)),
            small('−', st <= -ScoreAudioPlayer.maxSemitones ? null : () => a.setSemitones(st - 1)),
            Expanded(
              child: Center(
                child: Text(
                  st == 0
                      ? tr('Original', 'Original')
                      : tr(
                          '${st > 0 ? '+' : '−'}${st.abs()} Halbton${st.abs() == 1 ? '' : 'töne'}',
                          '${st > 0 ? '+' : '−'}${st.abs()} semitone${st.abs() == 1 ? '' : 's'}',
                        ),
                  style: theme.textTheme.titleMedium?.copyWith(color: st != 0 ? scheme.primary : null),
                ),
              ),
            ),
            small('+', st >= ScoreAudioPlayer.maxSemitones ? null : () => a.setSemitones(st + 1)),
            small('↺', st == 0 ? null : () => a.setSemitones(0), tip: tr('Originaltonhöhe', 'Original pitch')),
          ],
        ),
      ],
    ];
  }
}

/// Markiert die Schleife A–B unter dem Schieber.
class _LoopBar extends StatelessWidget {
  const _LoopBar({required this.length, required this.a, required this.b, required this.color});
  final Duration length;
  final Duration? a, b;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final total = length.inMilliseconds.clamp(1, 1 << 40);
    double f(Duration? d) => d == null ? 0 : (d.inMilliseconds / total).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final from = f(a) * w, to = b == null ? from + 3 : f(b) * w;
        return SizedBox(
          height: 4,
          child: Stack(
            children: [
              Positioned(
                left: from,
                width: (to - from).clamp(3.0, w),
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
