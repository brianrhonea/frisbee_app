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
    EventType.pickup => Icons.sports_handball_outlined,
    EventType.meeting => Icons.videocam_outlined,
  };

  /// Turf for time on the field, neutral for everything else. Amber is
  /// kept for what the user has to do, red for live games.
  Color color(ColorScheme scheme) => switch (this) {
    EventType.practice ||
    EventType.game ||
    EventType.tournament ||
    EventType.scrimmage ||
    EventType.pickup => scheme.primary,
    EventType.workout ||
    EventType.social ||
    EventType.meeting ||
    EventType.other => scheme.onSurfaceVariant,
  };
}

extension RsvpStyle on RsvpStatus {
  IconData get icon => switch (this) {
    RsvpStatus.going => Icons.check_circle,
    RsvpStatus.maybe => Icons.help,
    RsvpStatus.notGoing => Icons.cancel,
  };

  /// Turf for going, neutral otherwise: red is only for live games and
  /// amber only for what the user still has to do.
  Color color(ColorScheme scheme) => switch (this) {
    RsvpStatus.going => scheme.primary,
    RsvpStatus.maybe => scheme.onSurfaceVariant,
    RsvpStatus.notGoing => scheme.outline,
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
