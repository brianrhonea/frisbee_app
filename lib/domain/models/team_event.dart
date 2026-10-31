import 'model_utils.dart';

enum EventType {
  practice('Practice'),
  game('Game'),
  tournament('Tournament'),
  social('Social'),
  other('Other');

  const EventType(this.label);
  final String label;
}

enum RsvpStatus {
  going('Going'),
  maybe('Maybe'),
  notGoing("Can't go");

  const RsvpStatus(this.label);
  final String label;
}

/// Fixed reaction palette. Stored by name so security rules can validate it.
enum Reaction {
  thumbsUp('👍'),
  fire('🔥'),
  disc('🥏'),
  clap('🙌'),
  laugh('😂'),
  grimace('😬');

  const Reaction(this.emoji);
  final String emoji;
}

class PollOption {
  const PollOption({required this.id, required this.text});

  final String id;
  final String text;

  factory PollOption.fromMap(Map<String, dynamic> map) => PollOption(
    id: map['id'] as String? ?? '',
    text: map['text'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {'id': id, 'text': text};
}

class EventPoll {
  const EventPoll({
    required this.question,
    required this.options,
    this.multiple = false,
  });

  final String question;
  final List<PollOption> options;

  /// Whether members may pick more than one option.
  final bool multiple;

  factory EventPoll.fromMap(Map<String, dynamic> map) => EventPoll(
    question: map['question'] as String? ?? '',
    options: [
      for (final o in (map['options'] as List? ?? const []))
        PollOption.fromMap(Map<String, dynamic>.from(o)),
    ],
    multiple: map['multiple'] as bool? ?? false,
  );

  Map<String, dynamic> toMap() => {
    'question': question,
    'options': [for (final o in options) o.toMap()],
    'multiple': multiple,
  };
}

/// A practice, game or other team event on the team calendar.
///
/// [rsvps], [reactions] and [votes] are keyed by uid; each member may only
/// write their own entry (enforced by firestore.rules).
class TeamEvent {
  const TeamEvent({
    required this.id,
    required this.title,
    required this.startsAt,
    this.type = EventType.practice,
    this.endsAt,
    this.location = '',
    this.notes = '',
    this.poll,
    this.rsvps = const {},
    this.reactions = const {},
    this.votes = const {},
    this.createdBy,
  });

  /// Empty id means the event has not been saved yet.
  final String id;
  final String title;
  final EventType type;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String location;
  final String notes;
  final EventPoll? poll;
  final Map<String, RsvpStatus> rsvps;
  final Map<String, Set<Reaction>> reactions;

  /// uid → chosen [PollOption.id]s.
  final Map<String, List<String>> votes;
  final String? createdBy;

  bool get isNew => id.isEmpty;

  RsvpStatus? rsvpOf(String uid) => rsvps[uid];

  /// uids with [status].
  List<String> responders(RsvpStatus status) => [
    for (final e in rsvps.entries)
      if (e.value == status) e.key,
  ];

  /// Reaction → uids who used it, in palette order, omitting unused ones.
  Map<Reaction, List<String>> get reactionTally => {
    for (final r in Reaction.values)
      if (reactions.values.any((s) => s.contains(r)))
        r: [
          for (final e in reactions.entries)
            if (e.value.contains(r)) e.key,
        ],
  };

  /// uids who voted for [optionId].
  List<String> votersFor(String optionId) => [
    for (final e in votes.entries)
      if (e.value.contains(optionId)) e.key,
  ];

  /// Number of members who voted for at least one current option.
  int get voterCount {
    final ids = {for (final o in poll?.options ?? const <PollOption>[]) o.id};
    return votes.values.where((v) => v.any(ids.contains)).length;
  }

  TeamEvent copyWith({
    String? id,
    String? title,
    EventType? type,
    DateTime? startsAt,
    DateTime? Function()? endsAt,
    String? location,
    String? notes,
    EventPoll? Function()? poll,
  }) => TeamEvent(
    id: id ?? this.id,
    title: title ?? this.title,
    type: type ?? this.type,
    startsAt: startsAt ?? this.startsAt,
    endsAt: endsAt != null ? endsAt() : this.endsAt,
    location: location ?? this.location,
    notes: notes ?? this.notes,
    poll: poll != null ? poll() : this.poll,
    rsvps: rsvps,
    reactions: reactions,
    votes: votes,
    createdBy: createdBy,
  );

  factory TeamEvent.fromMap(String id, Map<String, dynamic> map) {
    final rawPoll = map['poll'];
    return TeamEvent(
      id: id,
      title: map['title'] as String? ?? '',
      type: enumByName(EventType.values, map['type'], EventType.other),
      startsAt: parseDate(map['startsAt']) ?? DateTime(1970),
      endsAt: parseDate(map['endsAt']),
      location: map['location'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      poll: rawPoll is Map
          ? EventPoll.fromMap(Map<String, dynamic>.from(rawPoll))
          : null,
      rsvps: {
        for (final e in ((map['rsvps'] as Map?) ?? const {}).entries)
          if (RsvpStatus.values.any((s) => s.name == e.value))
            e.key as String: enumByName(
              RsvpStatus.values,
              e.value,
              RsvpStatus.maybe,
            ),
      },
      reactions: {
        for (final e in ((map['reactions'] as Map?) ?? const {}).entries)
          e.key as String: {
            for (final name in (e.value as List? ?? const []))
              for (final r in Reaction.values)
                if (r.name == name) r,
          },
      },
      votes: {
        for (final e in ((map['votes'] as Map?) ?? const {}).entries)
          e.key as String: [
            for (final v in (e.value as List? ?? const [])) '$v',
          ],
      },
      createdBy: map['createdBy'] as String?,
    );
  }

  /// Fields editors may change. Responses are written per member.
  Map<String, dynamic> toEditableMap() => {
    'title': title,
    'type': type.name,
    'startsAt': startsAt,
    'endsAt': endsAt,
    'location': location,
    'notes': notes,
    'poll': poll?.toMap(),
  };
}
