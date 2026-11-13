import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/workout_recorder/workout_recorder.dart';
import '../../../domain/models/workout_route.dart';
import '../../../routing/routes.dart';
import '../../../utils/platform_support.dart';

/// Opens the GPS recorder. While a recording is going it says so, so the
/// user can find their way back to it. Nothing on platforms that can't
/// record.
class RecordWorkoutButton extends StatelessWidget {
  const RecordWorkoutButton({super.key, this.style, this.outlined = false});

  final ButtonStyle? style;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    if (!PlatformSupport.recordWorkouts) return const SizedBox.shrink();
    // Optional so pages built without it (tests) still render.
    final recorder = context.watch<WorkoutRecorder?>();
    final label = switch (recorder?.state) {
      RecorderState.recording =>
        'Recording · ${formatClock(recorder!.elapsed)}',
      RecorderState.paused => 'Paused · ${formatClock(recorder!.elapsed)}',
      RecorderState.finished =>
        'Share your ${recorder!.activity.label.toLowerCase()}',
      _ => 'Record',
    };
    final active =
        recorder != null &&
        recorder.state != RecorderState.idle &&
        recorder.state != RecorderState.ready;
    final icon = Icon(
      active ? Icons.fiber_manual_record : Icons.route_outlined,
      size: 18,
      color: active ? Theme.of(context).colorScheme.error : null,
    );
    void open() => context.push(Routes.recordWorkout);
    return outlined
        ? OutlinedButton.icon(
            style: style,
            onPressed: open,
            icon: icon,
            label: Text(label),
          )
        : TextButton.icon(
            style: style,
            onPressed: open,
            icon: icon,
            label: Text(label),
          );
  }
}
