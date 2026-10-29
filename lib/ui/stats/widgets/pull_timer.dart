import 'dart:async';

import 'package:flutter/material.dart';

typedef PullResult = ({String playerId, Duration hangTime, bool outOfBounds});

/// Times a pull: pick the puller, start on release, stop when it's caught
/// or lands. Returns null if cancelled.
Future<PullResult?> showPullTimer(
  BuildContext context, {
  required List<({String id, String name})> pullers,
  String? initial,
}) => showDialog<PullResult>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _PullTimer(pullers: pullers, initial: initial),
);

class _PullTimer extends StatefulWidget {
  const _PullTimer({required this.pullers, this.initial});

  final List<({String id, String name})> pullers;
  final String? initial;

  @override
  State<_PullTimer> createState() => _PullTimerState();
}

class _PullTimerState extends State<_PullTimer> {
  // A stopwatch is view state; only the final hang time is recorded.
  final _watch = Stopwatch();
  Timer? _ticker;
  late String? _puller = widget.initial;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _start() {
    _watch.start();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => setState(() {}),
    );
    setState(() {});
  }

  void _finish({required bool outOfBounds}) {
    _watch.stop();
    _ticker?.cancel();
    Navigator.pop<PullResult>(context, (
      playerId: _puller!,
      hangTime: _watch.elapsed,
      outOfBounds: outOfBounds,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final running = _watch.isRunning;
    final seconds = _watch.elapsedMilliseconds / 1000;
    return AlertDialog(
      title: const Text('Pull'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Who\'s pulling?', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in widget.pullers)
                  ChoiceChip(
                    label: Text(p.name),
                    selected: _puller == p.id,
                    onSelected: running
                        ? null
                        : (_) => setState(() => _puller = p.id),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                '${seconds.toStringAsFixed(1)} s',
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: running ? scheme.primary : null,
                ),
              ),
            ),
            Center(child: Text('Hang time', style: theme.textTheme.bodySmall)),
            const SizedBox(height: 20),
            if (!running)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: _puller == null ? null : _start,
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  _puller == null ? 'Pick the puller' : 'Start on release',
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        backgroundColor: Colors.green.shade600,
                      ),
                      onPressed: () => _finish(outOfBounds: false),
                      child: const Text(
                        'Caught / landed in',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        backgroundColor: scheme.error,
                        foregroundColor: scheme.onError,
                      ),
                      onPressed: () => _finish(outOfBounds: true),
                      child: const Text(
                        'Out of bounds',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
