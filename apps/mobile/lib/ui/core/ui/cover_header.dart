import 'package:flutter/material.dart';

import '../themes/theme.dart';
import 'balanced_text.dart';

/// A cover photo with the profile picture or team logo ([avatar]) sitting
/// on its lower edge, then the [title] and optional [subtitle] and
/// [actions] beneath (C5). Without a [coverUrl] (or while it loads or
/// fails) the cover is a quiet token-coloured band, so the layout never
/// jumps.
///
/// The cover is decoration: only the title block is read aloud. Text
/// below the cover grows with the text scale; the cover keeps its height.
///
/// Website counterpart: `CoverHeader` (apps/web).
class CoverHeader extends StatelessWidget {
  const CoverHeader({
    super.key,
    required this.title,
    required this.avatar,
    this.subtitle,
    this.coverUrl,
    this.actions = const [],
    this.coverHeight = 120,
    this.avatarSize = 72,
    this.roundAvatar = true,
  });

  final String title;
  final String? subtitle;

  /// The picture or logo, drawn at [avatarSize]: e.g. `Avatar(size: 72)`.
  final Widget avatar;
  final String? coverUrl;

  /// Buttons at the right of the title block, e.g. Follow or Message.
  final List<Widget> actions;
  final double coverHeight;
  final double avatarSize;

  /// A round picture (people, teams) or a rounded square (e.g. an event's
  /// date badge).
  final bool roundAvatar;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final url = coverUrl;
    final band = ColoredBox(color: c.accentSoft);
    final wrapActions = MediaQuery.textScalerOf(context).scale(14) > 14 * 1.3;
    final titleBlock = Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BalancedText(title, style: AppText.heading3.copyWith(color: c.ink)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: AppText.secondary.copyWith(color: c.muted)),
          ],
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The avatar overlaps the cover's lower edge by half its height.
        Stack(
          clipBehavior: Clip.none,
          fit: StackFit.passthrough,
          children: [
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Container(
                  height: coverHeight,
                  foregroundDecoration: BoxDecoration(
                    border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: url == null || url.isEmpty
                      ? band
                      : Image.network(
                          url,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, progress) =>
                              progress == null ? child : band,
                          errorBuilder: (_, _, _) => band,
                        ),
                ),
              ),
            ),
            Positioned(
              left: AppSpace.lg,
              bottom: -avatarSize / 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: roundAvatar ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: roundAvatar
                      ? null
                      : BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: c.background, width: 4),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: roundAvatar ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius: roundAvatar
                        ? null
                        : BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: c.border),
                  ),
                  position: DecorationPosition.foreground,
                  child: roundAvatar
                      ? ClipOval(child: avatar)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          child: avatar,
                        ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: avatarSize / 2 + AppSpace.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: wrapActions && actions.isNotEmpty
              // Large text: the buttons drop under the title and wrap.
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleBlock,
                    const SizedBox(height: AppSpace.md),
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: actions,
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: titleBlock),
                    if (actions.isNotEmpty) ...[
                      const SizedBox(width: AppSpace.md),
                      Wrap(spacing: AppSpace.sm, children: actions),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}
