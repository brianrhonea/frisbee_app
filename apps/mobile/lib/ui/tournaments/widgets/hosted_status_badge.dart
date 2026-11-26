import 'package:flutter/material.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../core/ui/scoreboard.dart';
import '../../core/ui/tone.dart';
import '../../core/ui/status_pill.dart';

/// Each status's dot color (website parity: registration green, live red,
/// the rest grey). Amber is kept for what's the user's to do, so no status
/// is amber.
extension HostedStatusTone on HostedStatus {
  Tone get tone => switch (this) {
    HostedStatus.draft => Tone.grey,
    HostedStatus.registration => Tone.green,
    HostedStatus.seeding => Tone.grey,
    HostedStatus.scheduled => Tone.grey,
    HostedStatus.live => Tone.red,
    HostedStatus.finished => Tone.grey,
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

/// A tournament's status as a [StatusPill]: red with its dot when live,
/// green while registration is open, grey otherwise.
class HostedStatusBadge extends StatelessWidget {
  const HostedStatusBadge({super.key, required this.status});

  final HostedStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
    HostedStatus.live => LivePill(label: status.label),
    HostedStatus.registration => StatusPill(
      status.label,
      tone: PillTone.success,
    ),
    _ => StatusPill(status.label),
  };
}
