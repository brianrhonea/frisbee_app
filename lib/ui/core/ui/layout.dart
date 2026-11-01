import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../themes/theme.dart';

/// The three layouts the app is designed for.
enum ScreenSize {
  /// Phones: bottom navigation bar, single column.
  mobile,

  /// Tablets and narrow windows: icon rail, single column.
  tablet,

  /// Desktops and wide windows: full sidebar, side column on pages.
  desktop;

  static const tabletWidth = 720.0;
  static const desktopWidth = 1200.0;

  static ScreenSize forWidth(double width) => width >= desktopWidth
      ? desktop
      : width >= tabletWidth
      ? tablet
      : mobile;

  static ScreenSize of(BuildContext context) =>
      forWidth(MediaQuery.sizeOf(context).width);

  bool get isMobile => this == mobile;
}

/// Width of page content at which a page shows its side column.
const sideColumnBreakpoint = 860.0;

/// Width of a page's side column.
const sideColumnWidth = 300.0;

/// Widest a page's content grows.
const maxPageWidth = 1180.0;

/// Outer padding of a page for [size].
EdgeInsets pagePadding(ScreenSize size) => switch (size) {
  ScreenSize.mobile => const EdgeInsets.fromLTRB(14, 16, 14, 32),
  ScreenSize.tablet => const EdgeInsets.fromLTRB(20, 20, 20, 40),
  ScreenSize.desktop => const EdgeInsets.fromLTRB(28, 24, 28, 40),
};

/// A scrolling page: content centered, capped at [maxPageWidth] and padded
/// for the screen size.
class PageScroll extends StatelessWidget {
  const PageScroll({super.key, required this.children, this.controller});

  final List<Widget> children;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final size = ScreenSize.of(context);
    return SingleChildScrollView(
      controller: controller,
      padding: pagePadding(size),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxPageWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// The main column with a [sideColumnWidth] column beside it when there's
/// room; otherwise [narrow] (default: main then side).
class SideColumnLayout extends StatelessWidget {
  const SideColumnLayout({
    super.key,
    required this.main,
    required this.side,
    this.narrow,
  });

  final List<Widget> main;
  final List<Widget> side;
  final List<Widget>? narrow;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      Widget column(List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: spaced(children),
      );
      if (constraints.maxWidth < sideColumnBreakpoint) {
        return column(narrow ?? [...main, ...side]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: column(main)),
          const SizedBox(width: 20),
          SizedBox(width: sideColumnWidth, child: column(side)),
        ],
      );
    },
  );
}

/// [children] with [gap] between each.
List<Widget> spaced(List<Widget> children, {double gap = 14}) => [
  for (var i = 0; i < children.length; i++) ...[
    if (i > 0) SizedBox(height: gap),
    children[i],
  ],
];

/// Small uppercase label above a heading, e.g. "UP NEXT · FALL LEAGUE".
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: color ?? AppColors.of(context).muted,
    ),
  );
}

/// A page's title block: eyebrow, big title, subtitle, and [action]
/// (e.g. "Create post") on the right.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final mobile = ScreenSize.of(context).isMobile;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[Eyebrow(eyebrow!), const SizedBox(height: 6)],
        Text(
          title,
          style: TextStyle(
            fontSize: mobile ? 24 : 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.9,
            height: 1.15,
            color: c.ink,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: TextStyle(color: c.muted, fontSize: 13.5)),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: text),
          if (action != null) ...[const SizedBox(width: 12), action!],
        ],
      ),
    );
  }
}

/// A white card with an optional title row: [title], then [action] (e.g.
/// "See all") or [icon] on the right.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.action,
    this.icon,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
  });

  final Widget child;
  final String? title;
  final Widget? action;
  final IconData? icon;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      letterSpacing: -0.2,
                      color: c.ink,
                    ),
                  ),
                ),
                ?action,
                if (icon != null) Icon(icon, size: 18, color: c.muted),
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
    return Card(
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// A small "See all →" style link for card headers.
class CardLink extends StatelessWidget {
  const CardLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.arrow_forward, size: 13, color: c.ink),
          ],
        ),
      ),
    );
  }
}

/// A dark green card for the most important thing on a page, e.g. the next
/// game.
class FeatureCard extends StatelessWidget {
  const FeatureCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Material(
      color: c.feature,
      borderRadius: BorderRadius.circular(cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A lime, full-width call to action on a [FeatureCard].
class HighlightButton extends StatelessWidget {
  const HighlightButton({
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
    return SizedBox(
      width: double.infinity,
      child: icon == null
          ? FilledButton(style: style, onPressed: onPressed, child: Text(label))
          : FilledButton.icon(
              style: style,
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: Text(label),
            ),
    );
  }
}

/// A small rounded tag, e.g. "Mixed club" or "PINNED".
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.strong = false});

  final String text;

  /// Lime instead of the soft tint.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: strong ? c.highlight : c.accentSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: strong ? c.onHighlight : c.ink,
        ),
      ),
    );
  }
}

/// A big number over a small caption, e.g. "24 / ROSTERED".
class StatBlock extends StatelessWidget {
  const StatBlock({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 2),
        Eyebrow(label),
      ],
    );
  }
}

/// Month over day, e.g. "NOV / 02", for event rows.
class DateBadge extends StatelessWidget {
  const DateBadge({super.key, required this.date, this.size = 40});

  final DateTime date;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: size,
      height: size + 4,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateFormat.MMM().format(date).toUpperCase(),
            style: TextStyle(
              fontSize: size * 0.2,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: c.muted,
            ),
          ),
          Text(
            DateFormat('dd').format(date),
            style: TextStyle(
              fontSize: size * 0.42,
              height: 1.05,
              fontWeight: FontWeight.w800,
              color: c.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Initials of [name]: the first letters of its first two words.
String initialsOf(String name) {
  final letters = name
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .take(2)
      .map((w) => w[0].toUpperCase())
      .join();
  return letters.isEmpty ? '?' : letters;
}

/// A person's photo, or their initials in a circle.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.radius = 20,
  });

  final String name;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final photo = photoUrl;
    final hasPhoto = photo != null && photo.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: c.accentSoft,
      foregroundColor: c.ink,
      backgroundImage: hasPhoto ? NetworkImage(photo) : null,
      child: hasPhoto
          ? null
          : Text(
              initialsOf(name),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: radius * 0.72,
              ),
            ),
    );
  }
}

/// A team's mark: a rounded dark green square with a mountain-like crest
/// (or a people icon for community groups).
class TeamBadge extends StatelessWidget {
  const TeamBadge({super.key, this.size = 40, this.community = false});

  final double size;
  final bool community;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.feature,
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Icon(
        community ? Icons.diversity_3_outlined : Icons.landscape_outlined,
        size: size * 0.56,
        color: c.highlight,
      ),
    );
  }
}

/// A count in a lime pill, for navigation items and list rows.
class CountPill extends StatelessWidget {
  const CountPill(this.count, {super.key, this.dark = false});

  final int count;

  /// Dark green with white text, e.g. on a lime background.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: dark ? c.feature : c.highlight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: dark ? c.onFeature : c.onHighlight,
        ),
      ),
    );
  }
}

/// "2 hours ago", "Yesterday", "Mon", or "Oct 3" for [time] relative to
/// [now].
String timeAgo(DateTime time, DateTime now) {
  final d = now.difference(time);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24 && DateUtils.isSameDay(time, now)) {
    final h = d.inHours;
    return '$h ${h == 1 ? 'hour' : 'hours'} ago';
  }
  final today = DateUtils.dateOnly(now);
  final days = today.difference(DateUtils.dateOnly(time)).inDays;
  if (days == 1) return 'Yesterday';
  if (days < 7) return DateFormat.E().format(time);
  return DateFormat.MMMd().format(time);
}

/// A row of text tabs with an underline under the selected one, e.g.
/// "Overview  Roster  Schedule". Scrolls sideways when it doesn't fit.
class UnderlineTabs extends StatelessWidget {
  const UnderlineTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  final List<String> labels;

  /// Index of the selected tab; -1 for none.
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              InkWell(
                onTap: () => onSelect(i),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(2, 10, 2, 10),
                  margin: const EdgeInsets.only(right: 22),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: i == selected ? c.ink : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: i == selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: i == selected ? c.ink : c.muted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
