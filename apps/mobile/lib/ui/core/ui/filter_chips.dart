import 'package:flutter/material.dart';

import '../themes/theme.dart';

/// One choice in [AppFilterChips]: [value] null is "All". [count] shows after
/// the label; [leading] is a small mark before it (a colour dot).
typedef FilterOption<T> = ({
  T? value,
  String label,
  int? count,
  Widget? leading,
});

/// A single-choice row of filter chips. The chosen chip is filled indigo
/// ([AppColors.chipOn]) with an [AppColors.onChipOn] label and a check, so it
/// never relies on colour alone. Every chip has a 48 px tap area, and the row
/// scrolls sideways when the chips don't fit, including at text scale 2.0.
///
/// Website counterpart: `FilterChip` (apps/web).
class AppFilterChips<T> extends StatelessWidget {
  const AppFilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.padding = EdgeInsets.zero,
  });

  final List<FilterOption<T>> options;

  /// The chosen value, or null for the "All" option.
  final T? selected;
  final ValueChanged<T?> onSelected;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: padding,
    child: Row(
      children: [
        for (final o in options)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: AppSpace.sm),
            child: AppFilterChip(
              label: o.count == null ? o.label : '${o.label} ${o.count}',
              leading: o.leading,
              selected: o.value == selected,
              onSelected: () => onSelected(o.value),
            ),
          ),
      ],
    ),
  );
}

/// One filter chip (see [AppFilterChips]).
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.leading,
  });

  final String label;
  final bool selected;

  /// Null shows the chip disabled.
  final VoidCallback? onSelected;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    // The selected chip gets a check as well as the fill.
    showCheckmark: true,
    avatar: leading,
    label: Text(label),
    selected: selected,
    onSelected: onSelected == null ? null : (_) => onSelected!(),
  );
}
