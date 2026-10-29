import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/team_event.dart';

extension EventTypeStyle on EventType {
  IconData get icon => switch (this) {
    EventType.practice => Icons.sports_outlined,
    EventType.game => Icons.sports_score,
    EventType.tournament => Icons.emoji_events_outlined,
    EventType.scrimmage => Icons.groups_2_outlined,
    EventType.workout => Icons.fitness_center,
    EventType.social => Icons.celebration_outlined,
    EventType.other => Icons.event_outlined,
  };

  Color color(ColorScheme scheme) => switch (this) {
    EventType.practice => scheme.primary,
    EventType.game => scheme.tertiary,
    EventType.tournament => Colors.amber.shade700,
    EventType.scrimmage => Colors.teal.shade500,
    EventType.workout => Colors.deepPurple.shade300,
    EventType.social => Colors.pink.shade400,
    EventType.other => scheme.outline,
  };
}

extension RsvpStyle on RsvpStatus {
  IconData get icon => switch (this) {
    RsvpStatus.going => Icons.check_circle,
    RsvpStatus.maybe => Icons.help,
    RsvpStatus.notGoing => Icons.cancel,
  };

  Color color(ColorScheme scheme) => switch (this) {
    RsvpStatus.going => Colors.green.shade600,
    RsvpStatus.maybe => Colors.amber.shade700,
    RsvpStatus.notGoing => scheme.error,
  };
}

/// "6:00 PM" or "6:00 PM – 8:00 PM".
String eventTimeRange(TeamEvent e) {
  final time = DateFormat.jm();
  final end = e.endsAt;
  if (end == null) return time.format(e.startsAt);
  if (DateUtils.isSameDay(e.startsAt, end)) {
    return '${time.format(e.startsAt)} – ${time.format(end)}';
  }
  return '${time.format(e.startsAt)} – '
      '${DateFormat.MMMd().add_jm().format(end)}';
}
