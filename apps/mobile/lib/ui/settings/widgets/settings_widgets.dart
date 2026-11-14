import 'package:flutter/material.dart';

import '../../core/themes/theme.dart';

/// A settings page: a back arrow, a title and grouped rows on the page
/// background, as on a phone's settings app.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: children,
      ),
    ),
  );
}

/// Rows under an optional small heading, on one card, with lines between.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    this.title,
    this.footer,
    required this.children,
  });

  final String? title;

  /// A note under the card, e.g. what a switch does.
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title case final t?)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                t.toUpperCase(),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: c.muted,
                ),
              ),
            ),
          Card(
            child: Column(
              children: [
                for (final (i, row) in children.indexed) ...[
                  if (i > 0) const Divider(indent: 56),
                  row,
                ],
              ],
            ),
          ),
          if (footer case final f?)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(f, style: TextStyle(fontSize: 12, color: c.muted)),
            ),
        ],
      ),
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

  /// For "Delete account" and the like.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    // A long value (an email address) goes under the title instead of
    // beside it, where it would squeeze the title to a letter a line.
    final long = (value?.length ?? 0) > 22 && subtitle == null;
    final side = long ? null : value;
    return ListTile(
      leading: Icon(icon, color: color ?? c.ink),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w600, color: color),
      ),
      subtitle: subtitle != null
          ? Text(subtitle!)
          : long
          ? Text(value!, style: TextStyle(color: c.muted, fontSize: 13))
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
                style: TextStyle(color: c.muted, fontSize: 13),
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
