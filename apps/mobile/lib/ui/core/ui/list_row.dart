import 'package:flutter/material.dart';

import '../themes/theme.dart';

/// One row of a list (C7): chats, notifications, members, teams.
/// [leading] (an avatar or icon), a [title] and [subtitle], and a
/// [trailing] widget such as a time or a pill.
///
/// * **Minimum height, not fixed.** 56 px, so it is a comfortable tap
///   target, and it grows with the text scale (the title wraps to two
///   lines before it is cut).
/// * [unread] sets the title in bold and adds an attention dot (read as
///   "Unread"). A [muted] row is set in the quiet text colour with a
///   "Muted" bell-off icon, and has no dot: muted rows don't ask for
///   attention.
/// * [selected] tints the row (the open chat on a wide screen).
///
/// Website counterpart: `ListRow` (apps/web).
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.unread = false,
    this.muted = false,
    this.selected = false,
    this.subtitleStyle,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool unread;
  final bool muted;
  final bool selected;
  final VoidCallback? onTap;

  /// Press and hold, or right-click: a menu of actions for the row.
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;

  /// Changes how the subtitle looks (e.g. an italic "typing...").
  final TextStyle? subtitleStyle;

  /// Shortest a row gets.
  static const minHeight = 56.0;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final titleColor = muted ? c.muted : c.ink;
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.sm + 2,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpace.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyStrong.copyWith(
                    fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                    color: titleColor,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.secondary
                        .copyWith(
                          color: muted ? c.muted : c.ink2,
                          fontWeight: unread
                              ? FontWeight.w600
                              : FontWeight.w400,
                        )
                        .merge(subtitleStyle),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpace.sm),
            trailing!,
          ],
          if (muted) ...[
            const SizedBox(width: AppSpace.sm),
            Icon(
              Icons.notifications_off_outlined,
              size: 16,
              color: c.muted,
              semanticLabel: 'Muted',
            ),
          ] else if (unread) ...[
            const SizedBox(width: AppSpace.sm),
            Semantics(
              label: 'Unread',
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: c.highlight,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    // Centred in the minimum height, so a one-line row has even space.
    final centred = Align(
      alignment: Alignment.centerLeft,
      heightFactor: 1,
      child: row,
    );
    return Semantics(
      selected: selected ? true : null,
      child: Material(
        color: selected ? c.accentSoft : Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minHeight),
          child: onTap == null
              ? centred
              : InkWell(
                  onTap: onTap,
                  onLongPress: onLongPress,
                  onSecondaryTap: onSecondaryTap,
                  child: centred,
                ),
        ),
      ),
    );
  }
}
