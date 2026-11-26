import 'package:flutter/material.dart';

import '../../core/themes/theme.dart';
import '../../core/ui/app_segmented_button.dart';

/// Shared pieces of the hat tournament, signup and draft screens in the
/// "Turf & Disc" design.

/// Colour of a gender match in splits and legends. MMP is turf, WMP the
/// secondary ink, so the two stay apart in light and dark without
/// borrowing the team / personal event colours. Null ("not set") is the
/// hairline grey.
Color genderColor(AppColors c, {required bool? mmp}) => switch (mmp) {
  true => c.accent,
  false => c.ink2,
  null => c.border2,
};

/// A thin bar split by gender match, e.g. 24 MMP | 20 WMP | 2 not set.
class GenderSplitBar extends StatelessWidget {
  const GenderSplitBar({
    super.key,
    required this.mmp,
    required this.wmp,
    this.unknown = 0,
    this.height = 8,
  });

  final int mmp;
  final int wmp;
  final int unknown;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final parts = [
      if (mmp > 0) (mmp, genderColor(c, mmp: true)),
      if (wmp > 0) (wmp, genderColor(c, mmp: false)),
      if (unknown > 0) (unknown, genderColor(c, mmp: null)),
    ];
    return Semantics(
      label:
          '$mmp MMP, $wmp WMP'
          '${unknown > 0 ? ', $unknown not set' : ''}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: parts.isEmpty
              ? ColoredBox(color: c.field)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, (n, color)) in parts.indexed) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(
                        flex: n,
                        child: ColoredBox(color: color),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

/// A small dot and label for a split legend, e.g. "● 24 MMP".
class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: c.ink2)),
      ],
    );
  }
}

/// A tab bar drawn as a segmented control, built from the shared
/// [AppSegment]: the selected tab is outlined in the accent. Reads the
/// enclosing [DefaultTabController]. For a few tabs that fit across.
class SegmentedTabBar extends StatelessWidget implements PreferredSizeWidget {
  const SegmentedTabBar({
    super.key,
    required this.labels,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 10),
  });

  final List<String> labels;
  final EdgeInsets padding;

  @override
  Size get preferredSize =>
      Size.fromHeight(AppSegmentedButton.minHeight + padding.vertical);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final controller = DefaultTabController.of(context);
    return Padding(
      padding: padding,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: c.card,
          shape: StadiumBorder(side: BorderSide(color: c.border2)),
        ),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: AppSegment(
                    selected: controller.index == i,
                    onTap: () => controller.animateTo(i),
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A soft amber panel for the one thing that is the user's to do, e.g.
/// "NEEDS YOU · ORGANIZER" over "Seed the bracket".
class NeedsYouPanel extends StatelessWidget {
  const NeedsYouPanel({
    super.key,
    required this.eyebrow,
    required this.title,
    this.message,
    this.action,
  });

  final String eyebrow;
  final String title;
  final String? message;

  /// Usually a full-width amber button.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.highlightSoft,
        borderRadius: BorderRadius.circular(cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: c.highlightInk,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 3),
            Text(message!, style: TextStyle(fontSize: 13, color: c.ink2)),
          ],
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    );
  }
}

/// A soft panel with an icon for a plain note, e.g. "The schedule is
/// published". [turf] tints it green for a hint about what to tap next.
class NotePanel extends StatelessWidget {
  const NotePanel({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.trailing,
    this.turf = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? trailing;
  final bool turf;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final fg = turf ? c.accentInk : c.ink;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: turf ? c.accentSoft : c.field,
        borderRadius: BorderRadius.circular(controlRadius),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: turf ? c.accentInk : c.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    message!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: turf ? c.accentInk : c.ink2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A full-width amber button for the user's to do (on a [NeedsYouPanel]).
class AmberButton extends StatelessWidget {
  const AmberButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final style = FilledButton.styleFrom(
      backgroundColor: c.highlight,
      foregroundColor: c.onHighlight,
      minimumSize: const Size.fromHeight(48),
      textStyle: const TextStyle(
        fontFamily: appFont,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
    return icon == null
        ? FilledButton(style: style, onPressed: onPressed, child: Text(label))
        : FilledButton.icon(
            style: style,
            onPressed: onPressed,
            icon: Icon(icon, size: 20),
            label: Text(label),
          );
  }
}

/// A section heading on the page background: 16/800 title and an
/// optional trailing widget (a button or link).
class HatHeading extends StatelessWidget {
  const HatHeading(this.text, {super.key, this.trailing, this.top = 20});

  final String text;
  final Widget? trailing;
  final double top;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: c.ink,
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
