import 'package:flutter/material.dart';

import '../themes/theme.dart';

/// Grey placeholders shaped like the content on the way, pulsing gently,
/// in place of a spinner. Put [SkeletonBox]es inside one [Skeleton] so
/// they pulse together.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child});

  final Widget child;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.45,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hold still for people who turn animations off.
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.value = 0.7;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    child: ExcludeSemantics(
      child: FadeTransition(opacity: _pulse, child: widget.child),
    ),
  );
}

/// One grey block: a line of text, an avatar ([circle]) or a photo.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.circle = false,
    this.radius = 6,
  });

  final double? width;
  final double height;
  final bool circle;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: circle ? height : width,
    height: height,
    decoration: ShapeDecoration(
      color: AppColors.of(context).accentSoft,
      shape: circle
          ? const CircleBorder()
          : RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(radius),
            ),
    ),
  );
}

/// A list row on the way: avatar, name and a line under it.
class SkeletonTile extends StatelessWidget {
  const SkeletonTile({super.key, this.titleWidth = 140});

  final double titleWidth;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        const SkeletonBox(height: 40, circle: true),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: titleWidth, height: 13),
              const SizedBox(height: 8),
              const FractionallySizedBox(
                widthFactor: 0.7,
                child: SkeletonBox(height: 10),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// A post on the way: author, a few lines of text and a photo.
class SkeletonPost extends StatelessWidget {
  const SkeletonPost({super.key});

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonTile(titleWidth: 120),
          SizedBox(height: 6),
          SkeletonBox(),
          SizedBox(height: 8),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: 0.8,
            child: SkeletonBox(),
          ),
          SizedBox(height: 14),
          SkeletonBox(height: 160, radius: cardRadius),
        ],
      ),
    ),
  );
}

/// Rows on the way, as many as fit (up to [count]). In a space too small
/// for a row, a small spinner instead.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 6, this.padding});

  final int count;
  final EdgeInsetsGeometry? padding;

  static const _rowHeight = 64.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = constraints.maxHeight;
      if (height < _rowHeight) {
        return const Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      final rows = height.isFinite
          ? ((height - 32) / _rowHeight).floor().clamp(1, count)
          : count;
      const widths = [150.0, 110.0, 170.0, 130.0, 90.0, 160.0];
      return ClipRect(
        child: Padding(
          padding: padding ?? const EdgeInsets.all(16),
          child: Skeleton(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < rows; i++)
                  SkeletonTile(titleWidth: widths[i % widths.length]),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// For `Image.frameBuilder`: fades a downloaded photo in over its
/// placeholder once it's decoded, rather than popping in.
Widget fadeInImageFrame(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
) {
  if (wasSynchronouslyLoaded) return child;
  return AnimatedOpacity(
    opacity: frame == null ? 0 : 1,
    alwaysIncludeSemantics: true,
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
    child: child,
  );
}

/// A photo on the way: a pulsing block the photo's size.
class SkeletonImage extends StatelessWidget {
  const SkeletonImage({super.key, this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) => Skeleton(
    child: SizedBox(
      width: width,
      height: height,
      child: const SkeletonBox(height: double.infinity, radius: 0),
    ),
  );
}
