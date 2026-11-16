import 'package:flutter/material.dart';

import '../../../domain/models/workout.dart';
import '../../core/themes/theme.dart';
import '../../posts/widgets/post_widgets.dart' show workoutIcon;

/// The activity picker for a workout: one row of small chips that scrolls
/// sideways, instead of a block of wrapped chips.
class ActivityPicker extends StatelessWidget {
  const ActivityPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    this.activities = WorkoutActivity.values,
  });

  final WorkoutActivity selected;
  final ValueChanged<WorkoutActivity> onSelected;
  final List<WorkoutActivity> activities;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final a in activities)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                labelPadding: const EdgeInsets.only(right: 4),
                avatar: Icon(
                  workoutIcon(a),
                  size: 16,
                  color: selected == a ? c.onAccent : c.muted,
                ),
                label: Text(a.label),
                selected: selected == a,
                showCheckmark: false,
                onSelected: (_) => onSelected(a),
              ),
            ),
        ],
      ),
    );
  }
}

/// Effort, 1 to 10, in one line: the label, a slider and the value, which
/// clears it when tapped. Not set until someone moves the slider.
class EffortRow extends StatelessWidget {
  const EffortRow({super.key, required this.effort, required this.onChanged});

  final int? effort;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final style = Theme.of(context).textTheme.bodyMedium;
    final value = effort;
    return Row(
      children: [
        Text('Effort', style: style?.copyWith(color: c.muted)),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              // Grey until set, so an untouched slider doesn't read as 5.
              activeTrackColor: value == null ? c.border : null,
              thumbColor: value == null ? c.muted : null,
            ),
            child: Slider(
              value: (value ?? 5).toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              label: '${value ?? 5}',
              semanticFormatterCallback: (v) =>
                  value == null ? 'Not set' : '${v.round()} out of 10',
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ),
        SizedBox(
          width: 52,
          child: value == null
              ? Text(
                  'Not set',
                  textAlign: TextAlign.end,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: c.muted),
                )
              : Tooltip(
                  message: 'Clear effort',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => onChanged(null),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '$value/10',
                        textAlign: TextAlign.end,
                        style: style?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// A workout box with what it's for written above it, always shown: a
/// label inside a short box on a phone is cut off or gone once typed in.
class WorkoutField extends StatelessWidget {
  const WorkoutField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: c.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// One exercise as its own small card: "Exercise 1" and a remove button,
/// the name across the full width, then sets, reps and weight, each with
/// its name above it.
class ExerciseCard extends StatelessWidget {
  const ExerciseCard({
    super.key,
    required this.index,
    required this.name,
    required this.sets,
    required this.reps,
    required this.weight,
    required this.onRemove,
  });

  final int index;
  final Widget name;
  final Widget sets;
  final Widget reps;
  final Widget weight;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 2, 2, 10),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(controlRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Exercise ${index + 1}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              IconButton(
                tooltip: 'Remove exercise',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                name,
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: WorkoutField(label: 'Sets', child: sets),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: WorkoutField(label: 'Reps', child: reps),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: WorkoutField(label: 'Weight', child: weight),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hints for an exercise's boxes, so an empty box shows what goes in it.
abstract final class ExerciseHints {
  static const name = 'What you did, e.g. Squats';
  static const sets = 'e.g. 3';
  static const reps = 'e.g. 10';
  static const weight = 'e.g. 135 lb';
}
