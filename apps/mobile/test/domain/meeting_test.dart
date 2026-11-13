import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/meeting/meeting_settings_repository.dart';
import 'package:frisbee_app/domain/models/meeting.dart';
import 'package:frisbee_app/domain/models/schedule_entry.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/routing/routes.dart';

import '../testing/fakes.dart';

void main() {
  final team = teamWith({
    'o': TeamRole.owner,
    'c': TeamRole.coach,
    'p1': TeamRole.player,
    'p2': TeamRole.player,
  });

  group('TeamMeeting', () {
    test('fromMap parses invites, status and RSVPs, skipping bad values', () {
      final m = TeamMeeting.fromMap('m1', {
        'title': 'Film',
        'startsAt': DateTime(2026, 11, 2, 19),
        'inviteRoles': ['player'],
        'inviteUsers': ['p9'],
        'requireApproval': true,
        'status': 'live',
        'rsvps': {'p1': 'attending', 'p2': 'notAttending', 'c': 'maybe'},
      });
      expect(m.inviteRoles, {TeamRole.player});
      expect(m.inviteUsers, {'p9'});
      expect(m.requireApproval, isTrue);
      expect(m.isLive, isTrue);
      expect(m.rsvps, {
        'p1': MeetingRsvp.attending,
        'p2': MeetingRsvp.notAttending,
      });
    });

    test('admins always see it; others by role or by name', () {
      final m = TeamMeeting(
        id: 'm1',
        title: 'Captains',
        startsAt: DateTime(2026),
        inviteUsers: const {'p1'},
      );
      expect(m.canSee(team, 'o'), isTrue);
      expect(m.canSee(team, 'c'), isTrue);
      expect(m.canSee(team, 'p1'), isTrue);
      expect(m.canSee(team, 'p2'), isFalse);
      expect(m.canSee(team, 'stranger'), isFalse);
      expect(m.invitees(team), unorderedEquals(['o', 'c', 'p1']));
      expect(m.audience, 'Admins + 1 person');
      final all = m.copyWith(inviteRoles: {TeamRole.player});
      expect(all.canSee(team, 'p2'), isTrue);
      expect(all.audience, 'Everyone');
    });

    test('approval applies to invitees, not admins', () {
      final m = TeamMeeting(
        id: 'm1',
        title: 'Film',
        startsAt: DateTime(2026),
        requireApproval: true,
      );
      expect(m.needsApproval(team, 'p1'), isTrue);
      expect(m.needsApproval(team, 'c'), isFalse);
    });

    test('toEditableMap writes roles in order and sorted users', () {
      final map = TeamMeeting(
        id: '',
        title: '  Film  ',
        startsAt: DateTime(2026),
        inviteRoles: const {TeamRole.player, TeamRole.coach},
        inviteUsers: const {'b', 'a'},
      ).toEditableMap();
      expect(map['title'], 'Film');
      expect(map['inviteRoles'], ['coach', 'player']);
      expect(map['inviteUsers'], ['a', 'b']);
      expect(map.containsKey('status'), isFalse);
      expect(map.containsKey('rsvps'), isFalse);
    });

    test('shows on the schedule as a meeting that links to its page', () {
      final m = TeamMeeting(
        id: 'm1',
        title: 'Film',
        startsAt: DateTime(2026, 11, 2, 19),
        rsvps: const {'p1': MeetingRsvp.attending},
      );
      final e = m.toEvent();
      expect(e.type, EventType.meeting);
      expect(e.rsvpOf('p1'), RsvpStatus.going);
      expect(Routes.teamEvent('t1', e), Routes.meeting('t1', 'm1'));
      final entry = ScheduleEntry(event: e, team: team);
      expect(entry.isMeeting, isTrue);
      expect(Routes.scheduleEvent(entry), '/team-meetings/t1/m1');
    });

    test('meetings are not a type events can be given', () {
      expect(EventType.editable, isNot(contains(EventType.meeting)));
    });
  });

  group('MeetingSettings', () {
    test('round-trips and clamps volumes', () {
      final s = MeetingSettings.fromJson({
        'outputVolume': 3,
        'participantVolumes': {'a': 1.5, 'b': -1},
        'audioInputId': 'mic',
        'cameraOn': true,
      });
      expect(s.outputVolume, 1);
      expect(s.volumeOf('a'), 1.5);
      expect(s.volumeOf('b'), 0);
      expect(s.volumeOf('c'), 1);
      expect(s.micOn, isTrue);
      final again = MeetingSettings.fromJson(s.toJson());
      expect(again.audioInputId, 'mic');
      expect(again.cameraOn, isTrue);
      expect(again.participantVolumes, s.participantVolumes);
    });
  });
}
