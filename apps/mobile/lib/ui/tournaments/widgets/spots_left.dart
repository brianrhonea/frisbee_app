import 'package:flutter/material.dart';

import '../../../domain/models/discover.dart';
import '../../core/themes/theme.dart';

/// "3 spots left" on a tournament card while registration is open: turf
/// while there's room, neutral "Full · waitlist" once there isn't. Never
/// amber, which is only for the user's own to-dos.
class SpotsLeft extends StatelessWidget {
  const SpotsLeft({super.key, required this.spots});

  final TournamentSpots spots;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Text(
      spots.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: spots.isFull ? FontWeight.w500 : FontWeight.w700,
        color: spots.isFull ? c.muted : c.accentInk,
      ),
    );
  }
}
