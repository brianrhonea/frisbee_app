import 'package:flutter/material.dart';

import '../themes/theme.dart';

/// One row of a [CoverMenuButton].
class CoverMenuItem {
  const CoverMenuItem({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;

  /// Drawn in the error colour (Block).
  final bool destructive;
}

/// The round "..." button over a cover photo that opens a short menu
/// (profiles: Report, Block, Share). A solid card-coloured disc keeps it
/// readable over any photo in light and dark, and it is a full 48 px
/// target labelled "More options" for screen readers.
///
/// Website counterpart: `CoverMenu` (apps/web).
class CoverMenuButton extends StatelessWidget {
  const CoverMenuButton({super.key, required this.items});

  final List<CoverMenuItem> items;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpace.xs),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.card.withValues(alpha: 0.92),
          shape: BoxShape.circle,
          border: Border.all(color: c.border),
        ),
        child: PopupMenuButton<int>(
          tooltip: 'More options',
          icon: Icon(Icons.more_horiz, color: c.ink),
          onSelected: (i) => items[i].onSelected(),
          itemBuilder: (_) => [
            for (var i = 0; i < items.length; i++)
              PopupMenuItem<int>(
                value: i,
                child: Row(
                  children: [
                    Icon(
                      items[i].icon,
                      size: 20,
                      color: items[i].destructive ? c.error : c.muted,
                    ),
                    const SizedBox(width: AppSpace.md),
                    Flexible(
                      child: Text(
                        items[i].label,
                        style: AppText.body.copyWith(
                          color: items[i].destructive ? c.error : c.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
