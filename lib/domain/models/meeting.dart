import 'model_utils.dart';
import 'team.dart';
import 'team_event.dart';

enum MeetingStatus {
  /// Not started yet; only admins can open the call, by starting it.
  scheduled,

  /// Started by an admin; invitees can join.
  live,
  ended,
}

enum MeetingRsvp {
  attending('Attending'),
  notAttending('Not attending');

  const MeetingRsvp(this.label);
  final String label;

  /// The schedule's RSVP status for this answer.
  RsvpStatus get asEventRsvp => switch (this) {
    attending => RsvpStatus.going,
    notAttending => RsvpStatus.notGoing,
  };
}

/// A video meeting on a team's schedule (`teams/{teamId}/meetings`).
///
/// Only invitees see it: members whose role is in [inviteRoles] or whose uid
/// is in [inviteUsers]. Admins (owners, coaches and captains) always see and
/// can join every meeting. firestore.rules and the `meetings` Cloud
/// Functions enforce the same; keep them in step.
class TeamMeeting {
  const TeamMeeting({
    required this.id,
    required this.title,
    required this.startsAt,
    this.endsAt,
    this.notes = '',
    this.inviteRoles = const {},
    this.inviteUsers = const {},
    this.requireApproval = false,
    this.status = MeetingStatus.scheduled,
    this.startedAt,
    this.endedAt,
    this.rsvps = const {},
    this.createdBy,
  });

  /// Empty for a meeting that hasn't been saved yet.
  final String id;
  final String title;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String notes;
  final Set<TeamRole> inviteRoles;
  final Set<String> inviteUsers;

  /// Invitees wait in the lobby until an admin lets them in.
  final bool requireApproval;
  final MeetingStatus status;
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// uid → answer; each invitee writes only their own.
  final Map<String, MeetingRsvp> rsvps;
  final String? createdBy;

  /// Most people a meeting can invite one by one; firestore.rules agrees.
  static const maxInviteUsers = 200;

  bool get isNew => id.isEmpty;
  bool get isLive => status == MeetingStatus.live;
  bool get isEnded => status == MeetingStatus.ended;

  MeetingRsvp? rsvpOf(String uid) => rsvps[uid];

  /// Whether member [uid] of [team] can see the meeting and RSVP.
  bool canSee(Team team, String uid) {
    final role = team.roleOf(uid);
    if (role == null) return false;
    return role.canEdit ||
        inviteRoles.contains(role) ||
        inviteUsers.contains(uid);
  }

  /// Members of [team] who can see the meeting.
  List<String> invitees(Team team) => [
    for (final uid in team.members.keys)
      if (canSee(team, uid)) uid,
  ];

  /// Whether [uid] would wait for an admin before joining.
  bool needsApproval(Team team, String uid) =>
      requireApproval && !team.canEdit(uid);

  /// One-line description of who's invited, for lists.
  String get audience {
    final others = TeamRole.values.where((r) => !r.canEdit).toList();
    if (others.every(inviteRoles.contains)) return 'Everyone';
    final people = inviteUsers.length;
    return [
      'Admins',
      for (final r in others)
        if (inviteRoles.contains(r)) r.pluralLabel,
      if (people > 0) '$people ${people == 1 ? 'person' : 'people'}',
    ].join(' + ');
  }

  /// uids with [answer].
  List<String> responders(MeetingRsvp answer) => [
    for (final e in rsvps.entries)
      if (e.value == answer) e.key,
  ];

  /// The meeting as a schedule entry, so calendars and lists can show it
  /// alongside events.
  TeamEvent toEvent() => TeamEvent(
    id: id,
    title: title,
    type: EventType.meeting,
    startsAt: startsAt,
    endsAt: endsAt,
    location: isLive ? 'Live now' : 'Video meeting',
    notes: notes,
    rsvps: {for (final e in rsvps.entries) e.key: e.value.asEventRsvp},
    createdBy: createdBy,
  );

  TeamMeeting copyWith({
    String? id,
    String? title,
    DateTime? startsAt,
    DateTime? Function()? endsAt,
    String? notes,
    Set<TeamRole>? inviteRoles,
    Set<String>? inviteUsers,
    bool? requireApproval,
  }) => TeamMeeting(
    id: id ?? this.id,
    title: title ?? this.title,
    startsAt: startsAt ?? this.startsAt,
    endsAt: endsAt != null ? endsAt() : this.endsAt,
    notes: notes ?? this.notes,
    inviteRoles: inviteRoles ?? this.inviteRoles,
    inviteUsers: inviteUsers ?? this.inviteUsers,
    requireApproval: requireApproval ?? this.requireApproval,
    status: status,
    startedAt: startedAt,
    endedAt: endedAt,
    rsvps: rsvps,
    createdBy: createdBy,
  );

  factory TeamMeeting.fromMap(String id, Map<String, dynamic> map) =>
      TeamMeeting(
        id: id,
        title: map['title'] as String? ?? '',
        startsAt: parseDate(map['startsAt']) ?? DateTime(1970),
        endsAt: parseDate(map['endsAt']),
        notes: map['notes'] as String? ?? '',
        inviteRoles: {
          for (final r in (map['inviteRoles'] as List?) ?? const [])
            enumByName(TeamRole.values, r, TeamRole.player),
        },
        inviteUsers: {
          for (final u in (map['inviteUsers'] as List?) ?? const []) '$u',
        },
        requireApproval: map['requireApproval'] as bool? ?? false,
        status: enumByName(
          MeetingStatus.values,
          map['status'],
          MeetingStatus.scheduled,
        ),
        startedAt: parseDate(map['startedAt']),
        endedAt: parseDate(map['endedAt']),
        rsvps: {
          for (final e in ((map['rsvps'] as Map?) ?? const {}).entries)
            if (MeetingRsvp.values.any((r) => r.name == e.value))
              '${e.key}': enumByName(
                MeetingRsvp.values,
                e.value,
                MeetingRsvp.attending,
              ),
        },
        createdBy: map['createdBy'] as String?,
      );

  /// Fields admins edit. Status and RSVPs have their own writes.
  Map<String, dynamic> toEditableMap() => {
    'title': title.trim(),
    'startsAt': startsAt,
    'endsAt': endsAt,
    'notes': notes,
    'inviteRoles': TeamRole.values
        .where(inviteRoles.contains)
        .map((r) => r.name)
        .toList(),
    'inviteUsers': (inviteUsers.toList()..sort()),
    'requireApproval': requireApproval,
  };
}

enum JoinRequestStatus { pending, admitted, denied }

/// An invitee asking to join a meeting that needs approval
/// (`teams/{teamId}/meetings/{meetingId}/requests/{uid}`).
class JoinRequest {
  const JoinRequest({
    required this.uid,
    required this.name,
    this.status = JoinRequestStatus.pending,
    this.requestedAt,
  });

  final String uid;
  final String name;
  final JoinRequestStatus status;
  final DateTime? requestedAt;

  bool get isPending => status == JoinRequestStatus.pending;
  bool get isAdmitted => status == JoinRequestStatus.admitted;
  bool get isDenied => status == JoinRequestStatus.denied;

  factory JoinRequest.fromMap(String uid, Map<String, dynamic> map) =>
      JoinRequest(
        uid: uid,
        name: map['name'] as String? ?? '',
        status: enumByName(
          JoinRequestStatus.values,
          map['status'],
          JoinRequestStatus.pending,
        ),
        requestedAt: parseDate(map['requestedAt']),
      );
}

/// What the app needs to connect to a meeting's call: the media server and
/// a short-lived join token from the `meetings-joinToken` Cloud Function.
class MeetingAccess {
  const MeetingAccess({required this.url, required this.token});

  final String url;
  final String token;
}
