import 'model_utils.dart';

/// How a community group's tournament is played.
enum TournamentFormat {
  roundRobin('Round robin', 'Everyone plays everyone; best record wins'),
  poolsSingleElim(
    'Pool play + single elimination',
    'Pools first, then a bracket seeded by pool finish',
  ),
  singleElim('Single elimination', 'Lose once and you are out'),
  doubleElim('Double elimination', 'Lose twice and you are out');

  const TournamentFormat(this.label, this.summary);
  final String label;
  final String summary;

  bool get hasPools => this == roundRobin || this == poolsSingleElim;
  bool get hasBracket => this != roundRobin;
}

enum TournamentStatus {
  /// Settings and teams are being worked out.
  setup,

  /// Games are generated and the schedule is published.
  scheduled,

  /// Every game that needs playing is final.
  done,
}

/// One team in a tournament: a name, its players and the captain who
/// reports scores. Only participants and organizers can see it.
class TournamentTeam {
  const TournamentTeam({
    required this.id,
    required this.name,
    this.captainId,
    this.playerIds = const [],
    this.playerNames = const {},
  });

  final String id;
  final String name;

  /// Reports and confirms this team's scores; one of [playerIds].
  final String? captainId;
  final List<String> playerIds;

  /// uid → display name.
  final Map<String, String> playerNames;

  String nameOf(String uid) => playerNames[uid] ?? 'Player';

  TournamentTeam copyWith({
    String? name,
    String? Function()? captainId,
    List<String>? playerIds,
    Map<String, String>? playerNames,
  }) => TournamentTeam(
    id: id,
    name: name ?? this.name,
    captainId: captainId != null ? captainId() : this.captainId,
    playerIds: playerIds ?? this.playerIds,
    playerNames: playerNames ?? this.playerNames,
  );

  factory TournamentTeam.fromMap(Map<String, dynamic> map) => TournamentTeam(
    id: '${map['id'] ?? ''}',
    name: '${map['name'] ?? ''}',
    captainId: map['captainId'] as String?,
    playerIds: [for (final p in (map['playerIds'] as List?) ?? const []) '$p'],
    playerNames: {
      for (final e in ((map['playerNames'] as Map?) ?? const {}).entries)
        '${e.key}': '${e.value}',
    },
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'captainId': captainId,
    'playerIds': playerIds,
    'playerNames': playerNames,
  };
}

/// What the organizer sets up before the schedule is generated.
class TournamentSettings {
  const TournamentSettings({
    required this.startsAt,
    this.format = TournamentFormat.poolsSingleElim,
    this.playersOnField = 5,
    this.poolCount = 2,
    this.gameMinutes = 40,
    this.breakMinutes = 10,
    this.scoreCap = 11,
    this.timeoutsPerHalf = 1,
    this.fields = 1,
    this.idealEndsAt,
    this.laterDays = const [],
  });

  static const fieldSizes = [3, 4, 5, 6, 7];

  /// Most teams a tournament can have (the rules allow 64).
  static const maxTeams = 64;

  final TournamentFormat format;

  /// 3 for 3v3 up to 7 for 7v7.
  final int playersOnField;

  /// For pool play; round robin is always one pool.
  final int poolCount;
  final int gameMinutes;

  /// Between games on the same field.
  final int breakMinutes;
  final int scoreCap;
  final int timeoutsPerHalf;

  /// Games played at the same time.
  final int fields;

  /// When the first day starts.
  final DateTime startsAt;

  /// When each later day starts, in order, for tournaments over several
  /// days.
  final List<DateTime> laterDays;

  /// When each day starts.
  List<DateTime> get days => [startsAt, ...laterDays];

  /// When the organizer would like to finish; the schedule warns if it
  /// runs past it.
  final DateTime? idealEndsAt;

  /// Pools actually used: round robin has one.
  int get pools => format == TournamentFormat.roundRobin ? 1 : poolCount;

  /// "5v5 · to 11 · 40 min · 1 timeout per half", plus the days.
  String get summary => [
    if (laterDays.isNotEmpty) '${days.length} days',
    '${playersOnField}v$playersOnField',
    'to $scoreCap',
    '$gameMinutes min',
    '$timeoutsPerHalf timeout${timeoutsPerHalf == 1 ? '' : 's'} per half',
  ].join(' · ');

  TournamentSettings copyWith({
    TournamentFormat? format,
    int? playersOnField,
    int? poolCount,
    int? gameMinutes,
    int? breakMinutes,
    int? scoreCap,
    int? timeoutsPerHalf,
    int? fields,
    DateTime? startsAt,
    DateTime? Function()? idealEndsAt,
    List<DateTime>? laterDays,
  }) => TournamentSettings(
    format: format ?? this.format,
    playersOnField: playersOnField ?? this.playersOnField,
    poolCount: poolCount ?? this.poolCount,
    gameMinutes: gameMinutes ?? this.gameMinutes,
    breakMinutes: breakMinutes ?? this.breakMinutes,
    scoreCap: scoreCap ?? this.scoreCap,
    timeoutsPerHalf: timeoutsPerHalf ?? this.timeoutsPerHalf,
    fields: fields ?? this.fields,
    startsAt: startsAt ?? this.startsAt,
    idealEndsAt: idealEndsAt != null ? idealEndsAt() : this.idealEndsAt,
    laterDays: laterDays ?? this.laterDays,
  );

  factory TournamentSettings.fromMap(Map<String, dynamic> map) =>
      TournamentSettings(
        format: enumByName(
          TournamentFormat.values,
          map['format'],
          TournamentFormat.poolsSingleElim,
        ),
        playersOnField: _int(map['playersOnField'], 5),
        poolCount: _int(map['poolCount'], 2),
        gameMinutes: _int(map['gameMinutes'], 40),
        breakMinutes: _int(map['breakMinutes'], 10),
        scoreCap: _int(map['scoreCap'], 11),
        timeoutsPerHalf: _int(map['timeoutsPerHalf'], 1),
        fields: _int(map['fields'], 1),
        startsAt: parseDate(map['startsAt']) ?? DateTime(1970),
        idealEndsAt: parseDate(map['idealEndsAt']),
        laterDays: [
          for (final d in (map['laterDays'] as List?) ?? const [])
            ?parseDate(d),
        ],
      );

  Map<String, dynamic> toMap() => {
    'format': format.name,
    'playersOnField': playersOnField,
    'poolCount': poolCount,
    'gameMinutes': gameMinutes,
    'breakMinutes': breakMinutes,
    'scoreCap': scoreCap,
    'timeoutsPerHalf': timeoutsPerHalf,
    'fields': fields,
    'startsAt': startsAt,
    'idealEndsAt': idealEndsAt,
    'laterDays': laterDays,
  };
}

int _int(Object? v, int fallback) => v is num ? v.toInt() : fallback;

/// A tournament a community group runs (`teams/{groupId}/groupTournaments`).
class GroupTournament {
  const GroupTournament({
    required this.id,
    required this.name,
    required this.settings,
    this.eventId,
    this.status = TournamentStatus.setup,
    this.teams = const [],
    this.createdBy,
    this.createdAt,
  });

  /// Empty until saved.
  final String id;
  final String name;

  /// The group's Tournament event whose RSVPs supply the players.
  final String? eventId;
  final TournamentSettings settings;
  final TournamentStatus status;
  final List<TournamentTeam> teams;
  final String? createdBy;
  final DateTime? createdAt;

  bool get isNew => id.isEmpty;

  /// Everyone on a team; they (and organizers) can see the tournament.
  List<String> get participantIds => [for (final t in teams) ...t.playerIds];

  /// teamId → captain uid, for the rules that check score reports.
  Map<String, String> get captains => {
    for (final t in teams) t.id: ?t.captainId,
  };

  TournamentTeam? team(String? id) =>
      teams.where((t) => t.id == id).firstOrNull;

  /// The team [uid] plays on, if any.
  TournamentTeam? teamOf(String uid) =>
      teams.where((t) => t.playerIds.contains(uid)).firstOrNull;

  String teamName(String? id) => team(id)?.name ?? 'TBD';

  GroupTournament copyWith({
    String? id,
    String? name,
    String? Function()? eventId,
    TournamentSettings? settings,
    TournamentStatus? status,
    List<TournamentTeam>? teams,
  }) => GroupTournament(
    id: id ?? this.id,
    name: name ?? this.name,
    eventId: eventId != null ? eventId() : this.eventId,
    settings: settings ?? this.settings,
    status: status ?? this.status,
    teams: teams ?? this.teams,
    createdBy: createdBy,
    createdAt: createdAt,
  );

  factory GroupTournament.fromMap(String id, Map<String, dynamic> map) =>
      GroupTournament(
        id: id,
        name: '${map['name'] ?? ''}',
        eventId: map['eventId'] as String?,
        settings: TournamentSettings.fromMap(
          Map<String, dynamic>.from((map['settings'] as Map?) ?? const {}),
        ),
        status: enumByName(
          TournamentStatus.values,
          map['status'],
          TournamentStatus.setup,
        ),
        teams: [
          for (final t in (map['teams'] as List?) ?? const [])
            if (t is Map) TournamentTeam.fromMap(Map<String, dynamic>.from(t)),
        ],
        createdBy: map['createdBy'] as String?,
        createdAt: parseDate(map['createdAt']),
      );

  /// Everything but createdBy/createdAt, which are set once.
  Map<String, dynamic> toMap() => {
    'name': name,
    'eventId': eventId,
    'settings': settings.toMap(),
    'status': status.name,
    'teams': [for (final t in teams) t.toMap()],
    'participantIds': participantIds,
    'captains': captains,
  };
}

/// Where a game's team comes from before it's known.
sealed class SlotSource {
  const SlotSource();

  static SlotSource? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return switch (raw['type']) {
      'winner' => WinnerOf('${raw['game']}'),
      'loser' => LoserOf('${raw['game']}'),
      'pool' => PoolRank('${raw['pool']}', _int(raw['rank'], 1)),
      _ => null,
    };
  }

  Map<String, dynamic> toMap();
}

class WinnerOf extends SlotSource {
  const WinnerOf(this.gameId);
  final String gameId;

  @override
  Map<String, dynamic> toMap() => {'type': 'winner', 'game': gameId};

  @override
  bool operator ==(Object other) => other is WinnerOf && other.gameId == gameId;

  @override
  int get hashCode => Object.hash('w', gameId);

  @override
  String toString() => 'W($gameId)';
}

class LoserOf extends SlotSource {
  const LoserOf(this.gameId);
  final String gameId;

  @override
  Map<String, dynamic> toMap() => {'type': 'loser', 'game': gameId};

  @override
  bool operator ==(Object other) => other is LoserOf && other.gameId == gameId;

  @override
  int get hashCode => Object.hash('l', gameId);

  @override
  String toString() => 'L($gameId)';
}

/// The team finishing [rank] (1 = first) in pool [poolId].
class PoolRank extends SlotSource {
  const PoolRank(this.poolId, this.rank);
  final String poolId;
  final int rank;

  @override
  Map<String, dynamic> toMap() => {
    'type': 'pool',
    'pool': poolId,
    'rank': rank,
  };

  @override
  bool operator ==(Object other) =>
      other is PoolRank && other.poolId == poolId && other.rank == rank;

  @override
  int get hashCode => Object.hash(poolId, rank);

  @override
  String toString() => '$poolId$rank';
}

enum GameStage {
  pool('Pool'),
  winners('Bracket'),
  losers("Losers' bracket"),
  grandFinal('Final'),

  /// Double elimination's second final, played only if the losers'
  /// bracket team wins the first.
  reset('Final (if needed)');

  const GameStage(this.label);
  final String label;

  bool get isBracket => this != pool;
}

enum GameStatus {
  scheduled,

  /// One captain reported a score; the other must confirm it.
  reported,
  done,
}

/// A captain's report, waiting for the other captain.
class ScoreReport {
  const ScoreReport({
    required this.scoreA,
    required this.scoreB,
    required this.byTeamId,
  });

  final int scoreA;
  final int scoreB;

  /// The team whose captain reported it.
  final String byTeamId;

  static ScoreReport? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return ScoreReport(
      scoreA: _int(raw['scoreA'], 0),
      scoreB: _int(raw['scoreB'], 0),
      byTeamId: '${raw['byTeam'] ?? ''}',
    );
  }

  Map<String, dynamic> toMap() => {
    'scoreA': scoreA,
    'scoreB': scoreB,
    'byTeam': byTeamId,
  };
}

/// One game on the tournament schedule.
class GroupGame {
  const GroupGame({
    required this.id,
    required this.order,
    required this.stage,
    required this.round,
    required this.label,
    this.poolId,
    this.field = 1,
    this.startsAt,
    this.teamA,
    this.teamB,
    this.sourceA,
    this.sourceB,
    this.status = GameStatus.scheduled,
    this.scoreA,
    this.scoreB,
    this.report,
    this.ifNeeded = false,
  });

  final String id;

  /// Position on the schedule, for sorting.
  final int order;
  final GameStage stage;
  final int round;

  /// "Pool A · Round 1", "Semifinal".
  final String label;
  final String? poolId;
  final int field;
  final DateTime? startsAt;

  /// Team ids; null until known (bracket games wait on earlier results).
  final String? teamA;
  final String? teamB;

  /// Where [teamA] / [teamB] come from in the bracket.
  final SlotSource? sourceA;
  final SlotSource? sourceB;
  final GameStatus status;
  final int? scoreA;
  final int? scoreB;
  final ScoreReport? report;

  /// Only played if needed (double elimination's reset final).
  final bool ifNeeded;

  bool get isDone => status == GameStatus.done;
  bool get hasTeams => teamA != null && teamB != null;
  bool involves(String? teamId) =>
      teamId != null && (teamA == teamId || teamB == teamId);

  String? get winner => !isDone ? null : (scoreA! > scoreB! ? teamA : teamB);

  String? get loser => !isDone ? null : (scoreA! > scoreB! ? teamB : teamA);

  GroupGame copyWith({
    int? order,
    int? field,
    DateTime? startsAt,
    String? Function()? teamA,
    String? Function()? teamB,
    GameStatus? status,
    int? Function()? scoreA,
    int? Function()? scoreB,
    ScoreReport? Function()? report,
  }) => GroupGame(
    id: id,
    order: order ?? this.order,
    stage: stage,
    round: round,
    label: label,
    poolId: poolId,
    field: field ?? this.field,
    startsAt: startsAt ?? this.startsAt,
    teamA: teamA != null ? teamA() : this.teamA,
    teamB: teamB != null ? teamB() : this.teamB,
    sourceA: sourceA,
    sourceB: sourceB,
    status: status ?? this.status,
    scoreA: scoreA != null ? scoreA() : this.scoreA,
    scoreB: scoreB != null ? scoreB() : this.scoreB,
    report: report != null ? report() : this.report,
    ifNeeded: ifNeeded,
  );

  factory GroupGame.fromMap(String id, Map<String, dynamic> map) => GroupGame(
    id: id,
    order: _int(map['order'], 0),
    stage: enumByName(GameStage.values, map['stage'], GameStage.pool),
    round: _int(map['round'], 1),
    label: '${map['label'] ?? ''}',
    poolId: map['pool'] as String?,
    field: _int(map['field'], 1),
    startsAt: parseDate(map['startsAt']),
    teamA: map['teamA'] as String?,
    teamB: map['teamB'] as String?,
    sourceA: SlotSource.fromMap(map['sourceA']),
    sourceB: SlotSource.fromMap(map['sourceB']),
    status: enumByName(GameStatus.values, map['status'], GameStatus.scheduled),
    scoreA: (map['scoreA'] as num?)?.toInt(),
    scoreB: (map['scoreB'] as num?)?.toInt(),
    report: ScoreReport.fromMap(map['report']),
    ifNeeded: map['ifNeeded'] as bool? ?? false,
  );

  Map<String, dynamic> toMap() => {
    'order': order,
    'stage': stage.name,
    'round': round,
    'label': label,
    'pool': poolId,
    'field': field,
    'startsAt': startsAt,
    'teamA': teamA,
    'teamB': teamB,
    'sourceA': sourceA?.toMap(),
    'sourceB': sourceB?.toMap(),
    'status': status.name,
    'scoreA': scoreA,
    'scoreB': scoreB,
    'report': report?.toMap(),
    'ifNeeded': ifNeeded,
  };
}
