import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import '../themes/theme.dart';
import 'app_button.dart';
import 'avatar.dart';
import 'balanced_text.dart';
import 'scroll_to_top.dart';
import 'status_pill.dart';

export 'date_badge.dart';

/// The three layouts the app is designed for (the guide's breakpoints:
/// 600, 900 and 1200).
enum ScreenSize {
  /// Under 600: bottom navigation bar, single column.
  mobile,

  /// 600 to 899: icon rail, single column.
  tablet,

  /// 900 and up: full sidebar, side column on pages. From 1200 the shell
  /// also has room for a context panel ([ScreenSize.panelWidth]).
  desktop;

  static const tabletWidth = 600.0;
  static const desktopWidth = 900.0;

  /// From this width the shell may show a context panel beside the page.
  static const panelWidth = 1200.0;

  /// The shell's content (page and panel) never grows wider than this.
  static const maxShellWidth = 1600.0;

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
///
/// Tapping the status bar (iOS), or the page's tab again, scrolls it back
/// to the top (see [ScrollToTop]).
class PageScroll extends StatefulWidget {
  const PageScroll({
    super.key,
    required this.children,
    this.controller,
    this.onRefresh,
    this.bottomInset = 0,
  });

  final List<Widget> children;

  /// Extra room under the content, e.g. a floating button's height plus 16,
  /// so it never covers the last row.
  final double bottomInset;
  final ScrollController? controller;

  /// Pull down to refresh, when given.
  final Future<void> Function()? onRefresh;

  @override
  State<PageScroll> createState() => _PageScrollState();
}

class _PageScrollState extends State<PageScroll> {
  ScrollController? _own;

  ScrollController get _controller =>
      widget.controller ?? (_own ??= ScrollController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = ScreenSize.of(context);
    final controller = _controller;
    final scroll = SingleChildScrollView(
      controller: controller,
      physics: widget.onRefresh == null
          ? null
          : const AlwaysScrollableScrollPhysics(),
      padding: pagePadding(
        size,
      ).add(EdgeInsets.only(bottom: widget.bottomInset)),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxPageWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: widget.children,
          ),
        ),
      ),
    );
    final onRefresh = widget.onRefresh;
    return ScrollToTop(
      controller: controller,
      child: onRefresh == null
          ? scroll
          : RefreshIndicator(onRefresh: onRefresh, child: scroll),
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
    style: AppText.caption.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: color ?? AppColors.of(context).muted,
    ),
  );
}

/// A page's title block: eyebrow, big title, subtitle, and [action]
/// (e.g. "New message") on the right.
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
        BalancedText(
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
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
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

/// A small turf "See all" link for card headers.
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
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.xs,
          vertical: 4,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: c.accent,
          ),
        ),
      ),
    );
  }
}

/// A card in the feature colour for what is live or today, e.g. the next
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
    // The same edge as the standard card (see the card theme): the card
    // colour is white on a near-white page, so the border carries it.
    return Material(
      color: c.feature,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        side: BorderSide(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A full-width call to action on a [FeatureCard]: an [AppButton.primary]
/// that fills the width.
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
  Widget build(BuildContext context) =>
      AppButton.primary(label, onPressed: onPressed, icon: icon, expand: true);
}

/// A small tag, e.g. "Mixed club" or "PINNED": a [StatusPill].
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.strong = false, this.success = false});

  final String text;

  /// In the success colours, for a confirmed state such as "You're on it".
  final bool success;

  /// A quieter grey fill instead of the accent tint.
  final bool strong;

  @override
  Widget build(BuildContext context) => StatusPill(
    text,
    tone: strong
        ? PillTone.neutral
        : (success ? PillTone.success : PillTone.accent),
  );
}

/// The mark of an official organizer (Team.official), e.g. Stall 10, and
/// the events it hosts.
class OfficialBadge extends StatelessWidget {
  const OfficialBadge({super.key, this.label = 'Stall 10 verified'});

  /// Null for the icon alone.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final icon = Icon(Icons.verified, size: 15, color: c.accent);
    final text = label;
    if (text == null) return Tooltip(message: 'Stall 10 verified', child: icon);
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 2, 8, 2),
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: c.ink,
            ),
          ),
        ],
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
            fontFamily: scoreFont,
            fontSize: 30,
            height: 1.05,
            fontWeight: FontWeight.w800,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 2),
        Eyebrow(label),
      ],
    );
  }
}

/// Initials of [name]: the first letters of its first two words.
String initialsOf(String name) => initialsOfName(name);

/// A person's photo, or their initials in a circle: an [Avatar].
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
  Widget build(BuildContext context) =>
      Avatar(name: name, imageUrl: photoUrl, size: radius * 2);
}

/// A team's mark: its initials in the condensed face (a rounded square for a
/// team, a circle for a community), or a crest icon (or a people icon for
/// community groups) without a [name]: a [TeamLogo].
class TeamBadge extends StatelessWidget {
  const TeamBadge({
    super.key,
    this.size = 40,
    this.community = false,
    this.name,
  });

  final double size;
  final bool community;

  /// When given, the team's initials instead of an icon.
  final String? name;

  @override
  Widget build(BuildContext context) => TeamLogo(
    name: name,
    size: size,
    kind: community ? TeamLogoKind.community : TeamLogoKind.team,
    decorative: true,
  );
}

/// An unread count in a solid pill, for navigation items and rows: a
/// [StatusPill.count].
class CountPill extends StatelessWidget {
  const CountPill(this.count, {super.key, this.dark = false});

  final int count;

  /// Neutral (ink) instead of the accent, e.g. on a selected nav item.
  final bool dark;

  @override
  Widget build(BuildContext context) =>
      StatusPill.count(count, tone: dark ? PillTone.neutral : PillTone.accent);
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
                        color: i == selected ? c.accent : Colors.transparent,
                        width: 3,
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
