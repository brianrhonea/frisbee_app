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
