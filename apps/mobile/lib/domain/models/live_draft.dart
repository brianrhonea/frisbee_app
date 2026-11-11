import 'hosted_tournament.dart';
import 'model_utils.dart';

/// Where a captains' draft stands.
enum DraftStatus {
  /// Captains are picking.
  live,

  /// The host stopped the clock.
  paused,

  /// Every player has been picked; the host can still undo or finish.
  done,

  /// The host turned the picks into the division's teams.
  finished,
}

/// A captain in a draft, in draft order.
class DraftCaptain {
  const DraftCaptain({required this.uid, required this.name});

  final String uid;
  final String name;
}

/// One pick: [uid] went to [captainId]'s team.
class DraftPick {
  const DraftPick({required this.uid, required this.captainId});

  final String uid;
  final String captainId;
}

/// A player's skill and gender match, which only the host and the captains
/// can see.
typedef DraftDetail = ({int skill, GenderMatch? gender});

/// The captains' live draft at `tournaments/{id}/drafts/{divisionId}`: the
/// board everyone in the division can watch. The server writes it (see
/// functions/src/tournaments/draft.ts); `snakeIndex` and `onTheClock`
/// mirror draft_model.ts and share its expected turns.
class LiveDraft {
  const LiveDraft({
    required this.divisionId,
    required this.status,
    this.captains = const [],
    this.picks = const [],
    this.pool = const {},
    this.pickSeconds = 0,
    this.mixed = false,
    this.turnStartedAt,
  });

  final String divisionId;
  final DraftStatus status;

  /// In draft order.
  final List<DraftCaptain> captains;
  final List<DraftPick> picks;

  /// Everyone captains can pick, uid → name. Captains aren't in it.
  final Map<String, String> pool;

  /// Time a captain gets per pick, or 0 for no limit.
  final int pickSeconds;
  final bool mixed;
  final DateTime? turnStartedAt;

  bool get running => status == DraftStatus.live;

  /// Which captain (an index into the draft order) makes pick number
  /// [pick] (from 0): the order snakes back on every other round.
  static int snakeIndex(int captains, int pick) {
    final spot = pick % captains;
    return (pick ~/ captains).isEven ? spot : captains - 1 - spot;
  }

  /// Whose turn it is, or null once every player has been picked.
  String? get onTheClock {
    if (captains.isEmpty || picks.length >= pool.length) return null;
    return captains[snakeIndex(captains.length, picks.length)].uid;
  }

  Set<String> get pickedIds => {for (final p in picks) p.uid};

  /// Players nobody has picked, by name.
  List<MapEntry<String, String>> get available => [
    for (final e in pool.entries)
      if (!pickedIds.contains(e.key)) e,
  ]..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));

  /// [captainId]'s team so far: the captain, then their picks in order.
  List<String> teamOf(String captainId) => [
    captainId,
    for (final p in picks)
      if (p.captainId == captainId) p.uid,
  ];

  String nameOf(String uid) =>
      pool[uid] ??
      captains.where((c) => c.uid == uid).firstOrNull?.name ??
      'Player';

  /// Seconds left on the clock at [now], or null with no time limit or
  /// when nobody is picking.
  int? secondsLeft(DateTime now) {
    final started = turnStartedAt;
    if (pickSeconds <= 0 || !running || started == null) return null;
    final left = pickSeconds - now.difference(started).inSeconds;
    return left < 0 ? 0 : left;
  }

  factory LiveDraft.fromMap(String divisionId, Map<String, dynamic> map) =>
      LiveDraft(
        divisionId: divisionId,
        status: enumByName(DraftStatus.values, map['status'], DraftStatus.live),
        captains: [
          for (final c in (map['captains'] as List?) ?? const [])
            if (c is Map)
              DraftCaptain(
                uid: '${c['uid'] ?? ''}',
                name: '${c['name'] ?? 'Captain'}',
              ),
        ],
        picks: [
          for (final p in (map['picks'] as List?) ?? const [])
            if (p is Map)
              DraftPick(uid: '${p['uid']}', captainId: '${p['captainId']}'),
        ],
        pool: {
          for (final e in ((map['pool'] as Map?) ?? const {}).entries)
            '${e.key}': '${e.value}',
        },
        pickSeconds: (map['pickSeconds'] as num?)?.toInt() ?? 0,
        mixed: map['mixed'] == true,
        turnStartedAt: parseDate(map['turnStartedAt']),
      );

  /// Skill and gender from `details/pool`, uid → detail.
  static Map<String, DraftDetail> detailsFromMap(Map<String, dynamic> map) => {
    for (final e in ((map['players'] as Map?) ?? const {}).entries)
      '${e.key}': (
        skill: (((e.value as Map?)?['skill'] as num?)?.toInt() ?? 3).clamp(
          PlayerSignup.minSkill,
          PlayerSignup.maxSkill,
        ),
        gender: switch ((e.value as Map?)?['gender']) {
          'mmp' => GenderMatch.mmp,
          'wmp' => GenderMatch.wmp,
          _ => null,
        },
      ),
  };
}
