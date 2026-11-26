import 'package:flutter/material.dart';

import '../themes/theme.dart';
import 'status_pill.dart';

/// A color for a tournament's status or a team's kind. Each has a light- and
/// a dark-theme shade.
///
/// The rule (zinc + indigo): kinds and most statuses are grey; red is for
/// live, green only for success (open, done), amber only for what needs the
/// user. There are no other hues, so a new tag cannot pick one by accident.
enum Tone {
  grey(Color(0xFF6B7280), Color(0xFFB0B7C3)),
  amber(Color(0xFFB7791F), Color(0xFFF2C46B)),
  red(Color(0xFFD03A2F), Color(0xFFF58A80)),
  // The success colours (AppColors.positive): green means done, open or OK.
  green(Color(0xFF166534), Color(0xFF86EFAC));

  const Tone(this._light, this._dark);
  final Color _light;
  final Color _dark;

  Color of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  /// The tone as text on its own tint ([tint] is the tint's opacity, 18%
  /// for a selected chip): the tone itself, moved toward black in the light
  /// theme (white in dark) just enough to reach 4.5:1 against the tint over
  /// the page or a card.
  Color ink(BuildContext context, {double tint = 0.18}) {
    final tone = of(context);
    final c = AppColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final grounds = [
      Color.alphaBlend(tone.withValues(alpha: tint), c.background),
      Color.alphaBlend(tone.withValues(alpha: tint), c.card),
    ];
    var ink = tone;
    for (var t = 0.0; t <= 1.0; t += 0.05) {
      ink = Color.lerp(tone, dark ? Colors.white : Colors.black, t)!;
      if (grounds.every((g) => _contrast(ink, g) >= 4.5)) break;
    }
    return ink;
  }

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }
}

/// A small pill in [tone]: a [StatusPill].
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
  Widget build(BuildContext context) =>
      StatusPill(label, tone: tone.pill, icon: icon);
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
              // Selected is the theme's indigo (chipOn) for every chip; the
              // tone shows only as the dot.
              onSelected: (_) => onSelected(f.value),
            ),
          ),
      ],
    ),
  );
}
