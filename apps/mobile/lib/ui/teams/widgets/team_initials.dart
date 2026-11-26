import 'package:flutter/material.dart';

import '../../../domain/models/team.dart';
import '../../core/ui/avatar.dart';

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
  Widget build(BuildContext context) => TeamLogo(
    name: name,
    size: size,
    kind: switch (kind) {
      TeamKind.team => TeamLogoKind.team,
      TeamKind.community => TeamLogoKind.community,
      TeamKind.organization => TeamLogoKind.organization,
    },
    decorative: true,
  );
}
