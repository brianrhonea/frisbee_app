import 'package:flutter/material.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../core/ui/tone.dart';

/// Each status's color, so a list reads at a glance.
extension HostedStatusTone on HostedStatus {
  Tone get tone => switch (this) {
    HostedStatus.draft => Tone.grey,
    HostedStatus.registration => Tone.blue,
    HostedStatus.seeding => Tone.amber,
    HostedStatus.scheduled => Tone.purple,
    HostedStatus.live => Tone.red,
    HostedStatus.finished => Tone.green,
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

/// A tournament's status as a colored tag.
class HostedStatusBadge extends StatelessWidget {
  const HostedStatusBadge({super.key, required this.status});

  final HostedStatus status;

  @override
  Widget build(BuildContext context) =>
      ToneTag(label: status.label, tone: status.tone, icon: status.icon);
}
