import 'package:flutter/material.dart';

import '../../../domain/models/team.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart' show initialsOf;

/// A team's or community's initials: a team-blue rounded square for a
/// team, a turf circle for a pickup community and a navy circle for a
/// school or club.
class TeamInitials extends StatelessWidget {
  const TeamInitials({
    super.key,
    required this.name,
    required this.kind,
    this.size = 44,
  });

  final String name;
  final TeamKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final (fill, ink) = switch (kind) {
      TeamKind.team => (c.badge, Colors.white),
      TeamKind.community => (c.accent, c.onAccent),
      TeamKind.organization => (c.feature, c.onFeature),
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(
          kind == TeamKind.team ? size * 0.27 : size / 2,
        ),
      ),
      child: Text(
        initialsOf(name),
        maxLines: 1,
        style: TextStyle(
          fontFamily: scoreFont,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.45,
          height: 1,
          color: ink,
        ),
      ),
    );
  }
}
