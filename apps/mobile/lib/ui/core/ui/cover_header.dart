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

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final url = coverUrl;
    final band = ColoredBox(color: c.accentSoft);
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
                  shape: BoxShape.circle,
                  border: Border.all(color: c.background, width: 4),
                ),
                child: avatar,
              ),
            ),
          ],
        ),
        SizedBox(height: avatarSize / 2 + AppSpace.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BalancedText(
                        title,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          height: 1.15,
                          color: c.ink,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(color: c.muted, fontSize: 13.5),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
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
