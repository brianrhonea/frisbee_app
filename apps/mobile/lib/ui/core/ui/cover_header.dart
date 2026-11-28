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
    this.watermark,
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

  /// Opt-in designed default band (profiles): without a cover photo, an
  /// accent wash into the field colour, a faint diagonal stripe and these
  /// letters (the initials, at most two) drawn large and faint. Null keeps
  /// the plain band. Decoration only: never read aloud.
  final String? watermark;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final url = coverUrl;
    final mark = watermark?.trim();
    final band = mark == null || mark.isEmpty
        ? ColoredBox(color: c.accentSoft)
        : DefaultCoverBand(
            watermark: mark.length > 2 ? mark.substring(0, 2) : mark,
          );
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

/// The designed default band behind a profile without a header photo, from
/// colour tokens only: the accent mixed ~30% into the card colour fading to
/// the field colour at 135 degrees, a faint diagonal stripe (accent ~9%),
/// and the [watermark] letters as a large Barlow Condensed mark (accent
/// ~16%) at the lower right. Excluded from semantics.
///
/// Website counterpart: `.ui-cover-default` (apps/web ui.css).
class DefaultCoverBand extends StatelessWidget {
  const DefaultCoverBand({super.key, required this.watermark});

  final String watermark;

  static const _fontSize = 100.0;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.lerp(c.card, c.accent, 0.3)!, c.field],
              ),
            ),
          ),
          CustomPaint(
            painter: _StripePainter(c.accent.withValues(alpha: 0.09)),
          ),
          Positioned(
            right: AppSpace.lg,
            bottom: -_fontSize * 0.18,
            child: Text(
              watermark,
              maxLines: 1,
              softWrap: false,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontFamily: scoreFont,
                fontWeight: FontWeight.w800,
                fontSize: _fontSize,
                height: 1,
                letterSpacing: 2,
                color: c.accent.withValues(alpha: 0.16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 2 px stripes every 18 px, running up and to the right (perpendicular to
/// a 135 degree gradient).
class _StripePainter extends CustomPainter {
  const _StripePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    const step = 18 * 1.4142;
    for (var k = 0.0; k < size.width + size.height; k += step) {
      canvas.drawLine(
        Offset(k, 0),
        Offset(k - size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StripePainter old) => old.color != color;
}
