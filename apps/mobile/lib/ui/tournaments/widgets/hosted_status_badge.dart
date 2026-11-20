import 'package:flutter/material.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/scoreboard.dart';
import '../../core/ui/tone.dart';

/// Each status's color, so a list reads at a glance. Amber is kept for
/// what's the user's to do, so no status is amber.
extension HostedStatusTone on HostedStatus {
  Tone get tone => switch (this) {
    HostedStatus.draft => Tone.grey,
    HostedStatus.registration => Tone.green,
    HostedStatus.seeding => Tone.teal,
    HostedStatus.scheduled => Tone.blue,
    HostedStatus.live => Tone.red,
    HostedStatus.finished => Tone.purple,
  };

  IconData get icon => switch (this) {
    HostedStatus.draft => Icons.edit_note,
    HostedStatus.registration => Icons.how_to_reg_outlined,
    HostedStatus.seeding => Icons.format_list_numbered,
    HostedStatus.scheduled => Icons.event_available_outlined,
    HostedStatus.live => Icons.circle,
    HostedStatus.finished => Icons.emoji_events_outlined,
  };
}

/// A tournament's status as a small pill: red with its dot when live,
/// turf while registration is open, grey otherwise.
class HostedStatusBadge extends StatelessWidget {
  const HostedStatusBadge({super.key, required this.status});

  final HostedStatus status;

  @override
  Widget build(BuildContext context) {
    if (status == HostedStatus.live) return LivePill(label: status.label);
    final c = AppColors.of(context);
    final open = status == HostedStatus.registration;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: open ? c.accentSoft : c.field,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        maxLines: 1,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: open ? c.accentInk : c.ink2,
        ),
      ),
    );
  }
}
