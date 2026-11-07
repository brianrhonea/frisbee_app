import 'package:flutter/material.dart';

/// A color for telling kinds of things apart at a glance: a tournament's
/// status, a team's kind. Each has a light- and a dark-theme shade.
enum Tone {
  grey(Color(0xFF6B7280), Color(0xFFB0B7C3)),
  blue(Color(0xFF2F6FD0), Color(0xFF6AA6F5)),
  teal(Color(0xFF1F8A8A), Color(0xFF6FD3CF)),
  amber(Color(0xFFB7791F), Color(0xFFF2C46B)),
  purple(Color(0xFF8A4FD1), Color(0xFFB794EC)),
  red(Color(0xFFD03A2F), Color(0xFFF58A80)),
  green(Color(0xFF2F8F57), Color(0xFF8FD3A3));

  const Tone(this._light, this._dark);
  final Color _light;
  final Color _dark;

  Color of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;
}

/// A small pill in [tone]: tinted fill, [label] in the tone's color.
class ToneTag extends StatelessWidget {
  const ToneTag({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
  });

  final String label;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = tone.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// One filter in a [ToneFilterBar]: [value] null is "All".
typedef ToneFilter<T> = ({T? value, String label, Tone? tone, int count});

/// A row of single-choice filter chips, each with its tone's dot and a
/// count; scrolls sideways when it doesn't fit.
class ToneFilterBar<T> extends StatelessWidget {
  const ToneFilterBar({
    super.key,
    required this.filters,
    required this.selected,
    required this.onSelected,
    this.padding = EdgeInsets.zero,
  });

  final List<ToneFilter<T>> filters;
  final T? selected;
  final ValueChanged<T?> onSelected;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: padding,
    child: Row(
      children: [
        for (final f in filters)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              avatar: f.tone == null
                  ? null
                  : CircleAvatar(
                      radius: 5,
                      backgroundColor: f.tone!.of(context),
                    ),
              label: Text('${f.label} ${f.count}'),
              selected: f.value == selected,
              selectedColor: f.tone?.of(context).withValues(alpha: 0.18),
              onSelected: (_) => onSelected(f.value),
            ),
          ),
      ],
    ),
  );
}
