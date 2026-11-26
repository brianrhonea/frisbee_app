import 'package:flutter/material.dart';

import '../themes/theme.dart';

/// Initials of [name]: the first letters of its first two words, or "?".
String initialsOfName(String name) {
  final letters = name
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .take(2)
      .map((w) => w[0].toUpperCase())
      .join();
  return letters.isEmpty ? '?' : letters;
}

bool _hasUrl(String? url) => url != null && url.isNotEmpty;

/// A person: their photo, else their initials in a circle, else (no name
/// either) a person icon. The initials sit behind the photo, so a photo that
/// is slow or fails to load leaves the initials showing, never an empty ring.
///
/// Announced to screen readers as [name] (as an image) unless [decorative]
/// is true, for use beside the name where it would only repeat it.
///
/// Website counterpart: `Avatar` (apps/web).
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 40,
    this.decorative = false,
  });

  final String name;
  final String? imageUrl;

  /// Diameter.
  final double size;

  /// Hide from screen readers.
  final bool decorative;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final named = name.trim().isNotEmpty;
    final Widget face = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: c.accentSoft,
      child: named
          ? Text(
              initialsOfName(name),
              maxLines: 1,
              softWrap: false,
              // The initials scale with the circle, not the text size.
              textScaler: TextScaler.noScaling,
              style: AppText.label.copyWith(
                fontSize: size * 0.36,
                height: 1,
                fontWeight: FontWeight.w700,
                color: c.accentInk,
              ),
            )
          : Icon(Icons.person_outline, size: size * 0.55, color: c.accentInk),
    );
    final url = imageUrl;
    final Widget circle = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            face,
            if (_hasUrl(url))
              Image.network(
                url!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                // Fade in over the initials; on failure leave them.
                frameBuilder: (context, child, frame, sync) => sync
                    ? child
                    : AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: AppMotion.of(context, AppMotion.base),
                        child: child,
                      ),
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
    if (decorative) return ExcludeSemantics(child: circle);
    return Semantics(
      label: named ? name : 'Person',
      image: true,
      excludeSemantics: true,
      child: circle,
    );
  }
}

/// What a team logo stands for; sets its colours and shape.
enum TeamLogoKind {
  /// Rounded square in the badge colour.
  team,

  /// Circle in the accent colour.
  community,

  /// Circle in the soft accent colour (a school, club or organization).
  organization,
}

/// A team's, community's or organization's mark: its image, else its initials
/// in the condensed face, else (no name) a crest icon.
///
/// Website counterpart: `TeamLogo` (apps/web).
class TeamLogo extends StatelessWidget {
  const TeamLogo({
    super.key,
    this.name,
    this.imageUrl,
    this.kind = TeamLogoKind.team,
    this.size = 40,
    this.decorative = false,
  });

  /// Null shows a crest icon instead of initials.
  final String? name;
  final String? imageUrl;
  final TeamLogoKind kind;

  /// Width and height.
  final double size;

  /// Hide from screen readers (the name is next to it).
  final bool decorative;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final n = name?.trim();
    final initials = n != null && n.isNotEmpty;
    final round = kind != TeamLogoKind.team;
    final radius = BorderRadius.circular(
      initials ? (round ? size / 2 : size * 0.27) : size * 0.28,
    );
    final (fill, ink) = switch ((initials, kind)) {
      (false, _) => (c.accentSoft, c.accentInk),
      (_, TeamLogoKind.team) => (c.badge, c.onMedia),
      (_, TeamLogoKind.community) => (c.accent, c.onAccent),
      (_, TeamLogoKind.organization) => (c.accentSoft, c.accentInk),
    };
    final url = imageUrl;
    final Widget mark = ClipRRect(
      borderRadius: radius,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: fill),
        alignment: Alignment.center,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            Center(
              child: initials
                  ? Text(
                      initialsOfName(n),
                      maxLines: 1,
                      softWrap: false,
                      textScaler: TextScaler.noScaling,
                      style: AppText.scoreSmall.copyWith(
                        fontSize: size * 0.45,
                        height: 1,
                        color: ink,
                      ),
                    )
                  : Icon(
                      kind == TeamLogoKind.community
                          ? Icons.diversity_3_outlined
                          : Icons.landscape_outlined,
                      size: size * 0.56,
                      color: ink,
                    ),
            ),
            if (_hasUrl(url))
              Image.network(
                url!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                frameBuilder: (context, child, frame, sync) => sync
                    ? child
                    : AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: AppMotion.of(context, AppMotion.base),
                        child: child,
                      ),
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
    if (decorative) return ExcludeSemantics(child: mark);
    return Semantics(
      label: initials ? n : 'Team',
      image: true,
      excludeSemantics: true,
      child: mark,
    );
  }
}

/// One face in an [AvatarStack].
typedef AvatarItem = ({String name, String? imageUrl});

/// Overlapping avatars with a "+N" for the rest, e.g. who is going. Shows up
/// to [max] faces; each has a ring in the card colour so they read apart.
/// Announced as one image: "Ana, Ben and 3 more".
///
/// Website counterpart: `AvatarStack` (apps/web).
class AvatarStack extends StatelessWidget {
  const AvatarStack({
    super.key,
    required this.items,
    this.max = 4,
    this.size = 32,
    this.total,
  }) : assert(max > 0);

  final List<AvatarItem> items;

  /// Most faces to draw before the "+N".
  final int max;

  /// Diameter of each avatar.
  final double size;

  /// The true count when [items] is only the first few.
  final int? total;

  /// Width of the ring in the card colour.
  static const ringWidth = 2.0;

  /// How much of each face the next one covers.
  static const overlap = 0.3;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final count = total ?? items.length;
    final shown = items.length > max ? max : items.length;
    final extra = count - shown;
    final step = size * (1 - overlap);
    final slots = shown + (extra > 0 ? 1 : 0);
    if (slots == 0) return const SizedBox.shrink();
    final width = size + (slots - 1) * step;
    Widget ring(Widget child) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c.card, width: ringWidth),
      ),
      child: ClipOval(child: child),
    );
    final names = [for (final i in items.take(shown)) i.name];
    final label = extra > 0
        ? '${names.join(', ')} and $extra more'
        : names.length > 1
        ? '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}'
        : names.join();
    return Semantics(
      label: label,
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        height: size,
        child: Stack(
          children: [
            for (var i = 0; i < shown; i++)
              PositionedDirectional(
                start: i * step,
                child: ring(
                  Avatar(
                    name: items[i].name,
                    imageUrl: items[i].imageUrl,
                    size: size - ringWidth * 2,
                    decorative: true,
                  ),
                ),
              ),
            if (extra > 0)
              PositionedDirectional(
                start: shown * step,
                child: ring(
                  Container(
                    color: c.field,
                    alignment: Alignment.center,
                    child: Text(
                      '+$extra',
                      maxLines: 1,
                      softWrap: false,
                      textScaler: TextScaler.noScaling,
                      style: AppText.caption.copyWith(
                        fontSize: size * 0.34,
                        fontWeight: FontWeight.w700,
                        color: c.ink2,
                      ),
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
