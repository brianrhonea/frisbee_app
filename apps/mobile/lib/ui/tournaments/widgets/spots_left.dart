import 'package:flutter/material.dart';

import '../../../domain/models/discover.dart';
import '../../core/themes/theme.dart';

/// "3 spots left" on a tournament card while registration is open, or a
/// line per division ("Mixed: 3 left") when it has two or more: turf while
/// there's room, neutral once full. Never amber, which is only for the
/// user's own to-dos.
class SpotsLeft extends StatelessWidget {
  const SpotsLeft({super.key, required this.spots});

  final TournamentSpots spots;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    TextStyle style(bool full) => TextStyle(
      fontSize: 12.5,
      fontWeight: full ? FontWeight.w500 : FontWeight.w700,
      color: full ? c.muted : c.accentInk,
    );
    if (spots.divisions.length < 2) {
      return Text(
        spots.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style(spots.isFull),
      );
    }
    final lines = spots.lines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, d) in spots.divisions.indexed)
          Text(
            lines[i],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style(d.left <= 0),
          ),
      ],
    );
  }
}
