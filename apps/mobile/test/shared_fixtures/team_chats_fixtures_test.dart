// Shared vectors for a team's chat in the inbox (TeamChatSummary in
// lib/data/repositories/chat/team_chat_activity.dart), checked by
// packages/shared/test/team_chats_fixtures.test.ts against teamChatSummary
// in team_chats.ts. See fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/chat/team_chat_activity.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/notification.dart';
import 'package:frisbee_app/domain/models/team.dart';

import 'fixture_file.dart';
import 'package:frisbee_app/domain/models/mentions.dart';

final _team = Team(
  id: 't1',
  name: 'Flyers',
  division: Division.mixed,
  level: CompetitionLevel.club,
  ownerId: 'o',
  members: const {'o': TeamRole.owner},
);

Map<String, Object?> _room(
  String id,
  String name, {
  String? lastAt,
  bool voice = false,
  bool canRead = true,
}) => {
  'id': id,
  'name': name,
  'kind': voice ? 'voice' : 'text',
  'lastAt': lastAt,
  'canRead': canRead,
};

const _t0 = '2026-11-01T09:00:00.000';
const _t1 = '2026-11-01T09:05:00.000';
const _t2 = '2026-11-01T09:09:00.000';
const _t3 = '2026-11-01T10:00:00.000';

final _cases = <Map<String, Object?>>[
  {
    'name': 'no messages yet',
    'rooms': [_room('general', 'General')],
    'reads': <String, Object?>{},
  },
  {
    'name': 'one unread room opens it',
    'rooms': [
      _room('general', 'General', lastAt: _t0),
      _room('rides', 'Car Pool', lastAt: _t1),
    ],
    'reads': {'rides': _t1},
  },
  {
    'name': 'two unread: newest first, the newest opens',
    'rooms': [
      _room('general', 'General', lastAt: _t0),
      _room('rides', 'Car Pool', lastAt: _t1),
    ],
    'reads': <String, Object?>{},
  },
  {
    'name': 'more than two unread are counted',
    'rooms': [
      _room('general', 'General', lastAt: _t0),
      _room('rides', 'Car Pool', lastAt: _t1),
      _room('lines', 'Lines', lastAt: _t2),
      _room('film', 'Film', lastAt: _t3),
    ],
    'reads': <String, Object?>{},
  },
  {
    'name': 'all read: the newest room opens',
    'rooms': [
      _room('general', 'General', lastAt: _t1),
      _room('rides', 'Car Pool', lastAt: _t0),
    ],
    'reads': {'general': _t1, 'rides': _t2},
  },
  {
    'name': 'rooms the user cannot read and voice channels are left out',
    'rooms': [
      _room('general', 'General', lastAt: _t0),
      _room('staff', 'Staff', lastAt: _t3, canRead: false),
      _room('lounge', 'Lounge', lastAt: _t3, voice: true),
    ],
    'reads': {'general': _t0},
  },
  {
    'name': 'a read before the last message is unread',
    'rooms': [_room('general', 'General', lastAt: _t1)],
    'reads': {'general': _t0},
  },
  {
    'name': 'a muted room is never unread',
    'rooms': [
      _room('general', 'General', lastAt: _t0),
      _room('rides', 'Car Pool', lastAt: _t1),
    ],
    'reads': <String, Object?>{},
    'muted': ['rides'],
  },
  {
    'name': 'an unread mention says so and opens its room',
    'rooms': [
      _room('general', 'General', lastAt: _t2),
      _room('rides', 'Car Pool', lastAt: _t1),
    ],
    'reads': {'general': _t0},
    'mentions': [
      _mention('rides', 'Cam mentioned you: who drives?', _t1),
      _mention('general', 'Avery mentioned you: old', _t0),
    ],
  },
  {
    'name': 'a mention read already is not shown',
    'rooms': [_room('general', 'General', lastAt: _t1)],
    'reads': {'general': _t2},
    'mentions': [_mention('general', 'Cam mentioned you: hi', _t1)],
  },
  {
    'name': 'a named mention shows in a muted room; @everyone does not',
    'rooms': [
      _room('general', 'General', lastAt: _t2),
      _room('rides', 'Car Pool', lastAt: _t3),
    ],
    'reads': <String, Object?>{},
    'muted': ['general', 'rides'],
    'mentions': [
      _mention('general', 'Cam mentioned you: named', _t2),
      _mention('rides', 'Cam mentioned you: everyone', _t3, personal: false),
    ],
  },
];

Map<String, Object?> _mention(
  String roomId,
  String text,
  String at, {
  bool personal = true,
}) => {'roomId': roomId, 'text': text, 'at': at, 'personal': personal};

void main() {
  test('team chat summary (team_chats/summary.json)', () {
    checkFixture(
      'team_chats/summary.json',
      "TeamChatSummary.fromReadable: a team's chat in the inbox. Of the "
          'rooms the user can read (canRead), voice channels are left out; a '
          'room is unread when lastAt is after its read time (or never '
          'read). `unread` is newest first; `open` is the room a tap opens '
          '(the only unread one, else the newest, else the first); '
          '`subtitle` is what the row says. Rooms in `muted` (room ids, '
          'muted by the user) are never unread. An unread @mention (in '
          '`mentions`, after its room was read) makes the room unread, opens '
          'it and is the subtitle; a personal one even in a muted room.',
      [
        for (final c in _cases)
          () {
            final rooms = [
              for (final r in c['rooms']! as List<Map<String, Object?>>)
                if (r['canRead'] == true)
                  ChatRoom.fromMap(r['id']! as String, {
                    'name': r['name'],
                    'kind': r['kind'],
                    'lastAt': r['lastAt'] == null
                        ? null
                        : DateTime.parse(r['lastAt']! as String),
                  }),
            ];
            final reads = {
              for (final e in (c['reads']! as Map<String, Object?>).entries)
                e.key: DateTime.parse(e.value! as String),
            };
            final s = TeamChatSummary.fromReadable(
              _team,
              rooms,
              reads,
              muted: {
                for (final r in (c['muted'] as List<String>?) ?? const [])
                  NotificationPreferences.roomKey(_team.id, r),
              },
              mentions: [
                for (final m
                    in (c['mentions'] as List<Map<String, Object?>>?) ??
                        const <Map<String, Object?>>[])
                  ChatMention(
                    teamId: _team.id,
                    roomId: m['roomId']! as String,
                    text: m['text']! as String,
                    at: DateTime.parse(m['at']! as String),
                    personal: m['personal']! as bool,
                  ),
              ],
            );
            return {
              ...c,
              'summary': {
                'rooms': [for (final r in s.rooms) r.id],
                'unread': [for (final r in s.unreadRooms) r.id],
                'lastAt': s.lastAt,
                'open': s.openRoom?.id,
                'subtitle': s.subtitle,
                'mention': s.mention?.roomId,
              },
            };
          }(),
      ],
    );
  });
}
