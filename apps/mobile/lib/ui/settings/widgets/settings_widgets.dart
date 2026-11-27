import 'package:flutter/material.dart';

import '../../core/themes/theme.dart';

/// The bar on settings pages: the card colour with a hairline under it and
/// a 17/700 title.
PreferredSizeWidget settingsAppBar(
  BuildContext context, {
  required Widget title,
  List<Widget>? actions,
  bool automaticallyImplyLeading = true,
}) {
  final c = AppColors.of(context);
  return AppBar(
    title: title,
    actions: actions,
    automaticallyImplyLeading: automaticallyImplyLeading,
    backgroundColor: c.card,
    // Close to the back arrow, as in the mockups.
    titleSpacing: ModalRoute.of(context)?.impliesAppBarDismissal ?? false
        ? 4
        : null,
    titleTextStyle: AppText.section.copyWith(color: c.ink),
    shape: Border(bottom: BorderSide(color: c.border)),
  );
}

/// A settings page: a back arrow, a title and grouped rows on the page
/// background, as on a phone's settings app.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.title,
    this.actions,
    required this.children,
  });

  final String title;

  /// On the right of the bar, e.g. a count.
  final List<Widget>? actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: settingsAppBar(context, title: Text(title), actions: actions),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: children,
      ),
    ),
  );
}

/// A small uppercase heading over a settings card, e.g. "APPEARANCE".
class SettingsHeading extends StatelessWidget {
  const SettingsHeading(this.text, {super.key, this.trailing});

  final String text;

  /// After the heading, e.g. a count of invites.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Semantics(
      header: true,
      child: Row(
        children: [
          Flexible(
            child: Text(
              text.toUpperCase(),
              style: AppText.label.copyWith(
                letterSpacing: 0.6,
                color: AppColors.of(context).muted,
              ),
            ),
          ),
          if (trailing case final t?) ...[const SizedBox(width: 8), t],
        ],
      ),
    ),
  );
}

/// A note under a settings card, e.g. what a switch does.
class SettingsFooter extends StatelessWidget {
  const SettingsFooter(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
    child: Text(
      text,
      style: AppText.caption.copyWith(color: AppColors.of(context).muted),
    ),
  );
}

/// Rows under an optional small heading, on the page, with lines between.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    this.title,
    this.titleTrailing,
    this.footer,
    required this.children,
  });

  final String? title;

  /// After the title, e.g. a count.
  final Widget? titleTrailing;

  /// A note under the card, e.g. what a switch does.
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title case final t?) SettingsHeading(t, trailing: titleTrailing),
          // No outer card: the rows sit on the page under their heading,
          // with hairlines between, like the list rows elsewhere.
          // Rows (switches and radios too) in the settings type sizes.
          ListTileTheme.merge(
            tileColor: Colors.transparent,
            titleTextStyle: AppText.bodyStrong.copyWith(color: c.ink),
            subtitleTextStyle: AppText.caption.copyWith(color: c.muted),
            child: Column(
              children: [
                for (final (i, row) in children.indexed) ...[
                  if (i > 0) const Divider(),
                  row,
                ],
              ],
            ),
          ),
          if (footer case final f?) SettingsFooter(f),
        ],
      ),
    );
  }
}

/// A row's icon on a small rounded tile, as the leading of settings rows
/// (and of switches and radios beside them).
class SettingsIcon extends StatelessWidget {
  const SettingsIcon(this.icon, {super.key, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: c.field,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Icon(icon, size: 18, color: color ?? c.ink2),
    );
  }
}

/// One settings row: icon, label, optional value or note, and a chevron
/// when it opens a page.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.opensPage = true,
    this.color,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Shown on the right, e.g. "Dark".
  final String? value;
  final VoidCallback? onTap;
  final bool opensPage;

  /// A colour for the icon and label.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    // A long value (an email address) goes under the title instead of
    // beside it, where it would squeeze the title to a letter a line.
    final long = (value?.length ?? 0) > 22 && subtitle == null;
    final side = long ? null : value;
    return ListTile(
      minTileHeight: 52,
      leading: SettingsIcon(icon, color: color),
      title: Text(
        title,
        style: AppText.bodyStrong.copyWith(color: color ?? c.ink),
      ),
      subtitle: subtitle != null
          ? Text(subtitle!, style: AppText.caption.copyWith(color: c.muted))
          : long
          ? Text(value!, style: AppText.secondary.copyWith(color: c.muted))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (side case final v?)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                v,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.secondary.copyWith(color: c.muted),
              ),
            ),
          if (opensPage && onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: c.muted),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}
