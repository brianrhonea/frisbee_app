import 'follow.dart';
import 'group_tournament.dart';
import 'model_utils.dart';
import 'team.dart';

/// Who can take part in a hosted tournament. The page, schedule, results
/// and news are public either way.
enum TournamentVisibility {
  public('Public', 'Any team can apply'),
  inviteOnly('Invite only', 'Only teams you invite can play');

  const TournamentVisibility(this.label, this.summary);
  final String label;
  final String summary;
}

/// How teams get into a hosted tournament.
enum TournamentEntryType {
  /// Teams on the app register (club style).
  teams,

  /// Teams are built from players who RSVP'd (hat or pickup style).
  players,
}

/// What kind of event a hosted tournament is. A league runs a weekly
/// season (with optional playoffs) instead of one weekend.
enum HostedKind {
  tournament('Tournament'),
  league('League');

  const HostedKind(this.label);
  final String label;
}

/// The three kinds of hosted event, for filtering and badges.
enum HostedType {
  tournament('Tournament'),
  hat('Hat tournament'),
  league('League');

  const HostedType(this.label);
  final String label;
}

/// How teams are built from individual signups (player entry).
enum DraftMode {
  /// The app deals balanced teams from skill and gender.
  balanced('Balanced teams', 'Teams are dealt automatically, evened by skill'),

  /// The host picks captains, who take turns drafting players.
  captains('Captains draft', 'Captains take turns picking players');

  const DraftMode(this.label, this.summary);
  final String label;
  final String summary;
}

/// A league's season: how many weeks it runs and how the playoffs work.
/// The first night and its start time come from the division's
/// `settings.startsAt`; each following week is seven days on.
class LeagueSeason {
  const LeagueSeason({
    this.weeks = 8,
    this.playoffWeeks = 1,
    this.playoffTeams = 4,
    this.gamesPerNight = 1,
    this.skipDates = const [],
  });

  static const maxWeeks = 26;
  static const maxPlayoffWeeks = 3;
  static const playoffSizes = [0, 2, 4, 8];
  static const maxGamesPerNight = 2;
  static const maxSkipDates = 10;

  /// Total weeks, playoffs included.
  final int weeks;
  final int playoffWeeks;

  /// 0 for no playoffs.
  final int playoffTeams;
  final int gamesPerNight;

  /// Weeks with no games (holidays), as the date of that night.
  final List<DateTime> skipDates;

  bool get hasPlayoffs => playoffTeams > 0 && playoffWeeks > 0;

  /// Regular-season weeks.
  int get regularWeeks => hasPlayoffs ? weeks - playoffWeeks : weeks;

  LeagueSeason copyWith({
    int? weeks,
    int? playoffWeeks,
    int? playoffTeams,
    int? gamesPerNight,
    List<DateTime>? skipDates,
  }) => LeagueSeason(
    weeks: weeks ?? this.weeks,
    playoffWeeks: playoffWeeks ?? this.playoffWeeks,
    playoffTeams: playoffTeams ?? this.playoffTeams,
    gamesPerNight: gamesPerNight ?? this.gamesPerNight,
    skipDates: skipDates ?? this.skipDates,
  );

  static LeagueSeason? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return LeagueSeason(
      weeks: ((raw['weeks'] as num?)?.toInt() ?? 8).clamp(1, maxWeeks),
      playoffWeeks: ((raw['playoffWeeks'] as num?)?.toInt() ?? 0).clamp(
        0,
        maxPlayoffWeeks,
      ),
      playoffTeams: (raw['playoffTeams'] as num?)?.toInt() ?? 0,
      gamesPerNight: ((raw['gamesPerNight'] as num?)?.toInt() ?? 1).clamp(
        1,
        maxGamesPerNight,
      ),
      skipDates: [
        for (final d in (raw['skipDates'] as List?) ?? const [])
          if (parseDate(d) != null) parseDate(d)!,
      ],
    );
  }

  Map<String, dynamic> toMap() => {
    'weeks': weeks,
    'playoffWeeks': playoffWeeks,
    'playoffTeams': playoffTeams,
    'gamesPerNight': gamesPerNight,
    'skipDates': skipDates,
  };

  @override
  bool operator ==(Object other) =>
      other is LeagueSeason &&
      other.weeks == weeks &&
      other.playoffWeeks == playoffWeeks &&
      other.playoffTeams == playoffTeams &&
      other.gamesPerNight == gamesPerNight &&
      other.skipDates.length == skipDates.length &&
      [
        for (var i = 0; i < skipDates.length; i++) skipDates[i],
      ].every((d) => other.skipDates.contains(d));

  @override
  int get hashCode =>
      Object.hash(weeks, playoffWeeks, playoffTeams, gamesPerNight);
}

/// Where a hosted tournament is in its life.
enum HostedStatus {
  /// Only the host's managers can see it.
  draft('Draft'),

  /// Published; teams apply or accept invites.
  registration('Registration open'),

  /// Registration closed; the host is seeding.
  seeding('Seeding'),

  /// Schedules are published.
  scheduled('Scheduled'),

  /// Games are being played.
  live('Live'),

  /// Every division has its results.
  finished('Final');

  const HostedStatus(this.label);
  final String label;

  bool get isPublished => this != draft;
  bool get acceptsEntries => this == registration;
}

/// The fee a team pays to hold its spot. Stall 10 doesn't take payments
/// yet: the host says how to pay and marks each team paid.
class BidFee {
  const BidFee({
    required this.amountCents,
    this.currency = 'USD',
    this.instructions = '',
    this.dueAt,
  });

  final int amountCents;
  final String currency;

  /// How to pay, e.g. "Venmo @club-treasurer".
  final String instructions;
  final DateTime? dueAt;

  /// "$250" or "$250.50".
  String get label {
    final whole = amountCents ~/ 100;
    final cents = amountCents % 100;
    final symbol = currency == 'USD' ? r'$' : '$currency ';
    return cents == 0
        ? '$symbol$whole'
        : '$symbol$whole.${cents.toString().padLeft(2, '0')}';
  }

  static BidFee? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return BidFee(
      amountCents: (raw['amountCents'] as num?)?.toInt() ?? 0,
      currency: raw['currency'] as String? ?? 'USD',
      instructions: raw['instructions'] as String? ?? '',
      dueAt: parseDate(raw['dueAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'amountCents': amountCents,
    'currency': currency,
    'instructions': instructions,
    'dueAt': dueAt,
  };

  @override
  bool operator ==(Object other) =>
      other is BidFee &&
      other.amountCents == amountCents &&
      other.currency == currency &&
      other.instructions == instructions &&
      other.dueAt == dueAt;

  @override
  int get hashCode => Object.hash(amountCents, currency, instructions, dueAt);
}

/// What each player pays to enter a player-entry event. Same shape as a
/// team's [BidFee], and still stored under `bidFee`.
typedef EntryFee = BidFee;

/// A division's name, copied onto the tournament so lists don't need to
/// read every division.
class DivisionSummary {
  const DivisionSummary({
    required this.id,
    required this.division,
    required this.level,
  });

  final String id;
  final Division division;
  final CompetitionLevel level;

  /// "Club Mixed".
  String get label => '${level.label} ${division.label}';

  factory DivisionSummary.fromMap(Map<String, dynamic> map) => DivisionSummary(
    id: '${map['id'] ?? ''}',
    division: enumByName(Division.values, map['division'], Division.mixed),
    level: enumByName(
      CompetitionLevel.values,
      map['level'],
      CompetitionLevel.club,
    ),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'division': division.name,
    'level': level.name,
  };
}

/// A tournament a team, group or school/club hosts, at `tournaments/{id}`.
/// Members of the host with Manage events run it.
class HostedTournament {
  const HostedTournament({
    required this.id,
    required this.hostId,
    required this.hostName,
    required this.name,
    required this.startsOn,
    this.hostKind = TeamKind.community,
    this.hostOfficial = false,
    this.endsOn,
    this.description = '',
    this.location = '',
    this.visibility = TournamentVisibility.public,
    this.entryType = TournamentEntryType.teams,
    this.status = HostedStatus.draft,
    this.bidFee,
    this.kind = HostedKind.tournament,
    this.season,
    this.draftMode = DraftMode.balanced,
    this.divisions = const [],
    this.createdBy,
    this.createdAt,
  });

  static const maxDivisions = 12;

  /// Empty until saved.
  final String id;

  /// The team doc (team, group or school/club) hosting it.
  final String hostId;
  final String hostName;
  final TeamKind hostKind;

  /// Hosted by an official organizer ([Team.official]), e.g. Stall 10.
  /// The rules only allow it when the host team is official.
  final bool hostOfficial;
  final String name;
  final DateTime startsOn;
  final DateTime? endsOn;
  final String description;
  final String location;
  final TournamentVisibility visibility;
  final TournamentEntryType entryType;
  final HostedStatus status;

  /// Null when it's free to enter. For player entry this is the per-player
  /// [EntryFee]; for team entry it's the team's bid fee.
  final BidFee? bidFee;
  final HostedKind kind;

  /// Leagues only.
  final LeagueSeason? season;

  /// How player-entry teams are built.
  final DraftMode draftMode;
  final List<DivisionSummary> divisions;
  final String? createdBy;
  final DateTime? createdAt;

  bool get isNew => id.isEmpty;
  bool get isLeague => kind == HostedKind.league;

  /// Individuals sign up and teams are generated (a hat tournament, or a
  /// league that takes players).
  bool get takesPlayers => entryType == TournamentEntryType.players;

  /// A one-off hat tournament.
  bool get isHat => takesPlayers && !isLeague;

  /// What kind of event it is, for lists.
  HostedType get type => isLeague
      ? HostedType.league
      : isHat
      ? HostedType.hat
      : HostedType.tournament;

  EntryFee? get entryFee => bidFee;

  /// What follows and tagged posts use, the same shape as group
  /// tournaments: `tournament_{hostId}_{id}`.
  String get followKey => FollowTarget.tournamentKey(hostId, id);

  DivisionSummary? division(String id) =>
      divisions.where((d) => d.id == id).firstOrNull;

  HostedTournament copyWith({
    String? id,
    String? name,
    String? hostName,
    bool? hostOfficial,
    DateTime? startsOn,
    DateTime? Function()? endsOn,
    String? description,
    String? location,
    TournamentVisibility? visibility,
    HostedStatus? status,
    BidFee? Function()? bidFee,
    LeagueSeason? Function()? season,
    DraftMode? draftMode,
    List<DivisionSummary>? divisions,
  }) => HostedTournament(
    id: id ?? this.id,
    hostId: hostId,
    hostName: hostName ?? this.hostName,
    hostKind: hostKind,
    hostOfficial: hostOfficial ?? this.hostOfficial,
    name: name ?? this.name,
    startsOn: startsOn ?? this.startsOn,
    endsOn: endsOn != null ? endsOn() : this.endsOn,
    description: description ?? this.description,
    location: location ?? this.location,
    visibility: visibility ?? this.visibility,
    entryType: entryType,
    status: status ?? this.status,
    bidFee: bidFee != null ? bidFee() : this.bidFee,
    kind: kind,
    season: season != null ? season() : this.season,
    draftMode: draftMode ?? this.draftMode,
    divisions: divisions ?? this.divisions,
    createdBy: createdBy,
    createdAt: createdAt,
  );

  factory HostedTournament.fromMap(
    String id,
    Map<String, dynamic> map,
  ) => HostedTournament(
    id: id,
    hostId: map['hostId'] as String? ?? '',
    hostName: map['hostName'] as String? ?? '',
    hostKind: enumByName(TeamKind.values, map['hostKind'], TeamKind.community),
    hostOfficial: map['hostOfficial'] == true,
    name: map['name'] as String? ?? '',
    startsOn: parseDate(map['startsOn']) ?? DateTime(2000),
    endsOn: parseDate(map['endsOn']),
    description: map['description'] as String? ?? '',
    location: map['location'] as String? ?? '',
    visibility: enumByName(
      TournamentVisibility.values,
      map['visibility'],
      TournamentVisibility.public,
    ),
    entryType: enumByName(
      TournamentEntryType.values,
      map['entryType'],
      TournamentEntryType.teams,
    ),
    status: enumByName(HostedStatus.values, map['status'], HostedStatus.draft),
    bidFee: BidFee.fromMap(map['bidFee']),
    kind: enumByName(HostedKind.values, map['kind'], HostedKind.tournament),
    season: LeagueSeason.fromMap(map['season']),
    draftMode: enumByName(
      DraftMode.values,
      map['draftMode'],
      DraftMode.balanced,
    ),
    divisions: [
      for (final d in (map['divisions'] as List?) ?? const [])
        if (d is Map) DivisionSummary.fromMap(Map<String, dynamic>.from(d)),
    ],
    createdBy: map['createdBy'] as String?,
    createdAt: parseDate(map['createdAt']),
  );

  /// Everything but createdBy/createdAt, which are set once.
  Map<String, dynamic> toMap() => {
    'hostId': hostId,
    'hostName': hostName,
    'hostKind': hostKind.name,
    'hostOfficial': hostOfficial,
    'name': name,
    'startsOn': startsOn,
    'endsOn': endsOn,
    'description': description,
    'location': location,
    'visibility': visibility.name,
    'entryType': entryType.name,
    'status': status.name,
    'bidFee': bidFee?.toMap(),
    'kind': kind.name,
    'season': season?.toMap(),
    'draftMode': draftMode.name,
    'divisions': [for (final d in divisions) d.toMap()],
  };
}

/// One division of a hosted tournament, at
/// `tournaments/{id}/divisions/{divisionId}`: its own teams, format,
/// seeds, schedule and results.
class TournamentDivision {
  const TournamentDivision({
    required this.id,
    required this.division,
    required this.level,
    required this.settings,
    this.maxTeams = 16,
    this.seeds = const [],
    this.captains = const {},
    this.placements = const [],
    this.minRoster,
    this.teams = const [],
  });

  /// Whole numbers only; the engine handles up to [TournamentSettings.maxTeams].
  static const teamCaps = [4, 6, 8, 10, 12, 16, 20, 24, 32];

  static const maxMinRoster = 30;

  /// What divisions needed before it was a setting: a full club roster.
  static const defaultMinRoster = 7;

  /// Players a team needs on its roster to apply or accept an invite. Null
  /// means [defaultMinRoster]; the form sets it from the field size.
  final int? minRoster;

  /// Teams built from individual signups (player entry). Empty until the
  /// host drafts them.
  final List<TournamentTeam> teams;

  /// The roster size a team must reach: the host's setting, or the default.
  int get effectiveMinRoster => minRoster ?? defaultMinRoster;

  /// Ids of the real teams a league makes from its drafted ones start with
  /// this (functions/src/tournaments/league.ts).
  static const leagueTeamPrefix = 'league_';

  /// Every drafted team has become a real team (a league that takes
  /// players): from then on rosters are managed on the teams themselves.
  bool get teamsCreated =>
      teams.isNotEmpty && teams.every((t) => t.id.startsWith(leagueTeamPrefix));

  final String id;
  final Division division;
  final CompetitionLevel level;

  /// Format and game rules.
  final TournamentSettings settings;
  final int maxTeams;

  /// Accepted teams' ids in seed order (seed 1 first). The host reorders
  /// them until the schedule is published.
  final List<String> seeds;

  /// teamId → the uids who report that team's scores.
  final Map<String, List<String>> captains;

  /// Team ids by final place (1st first), once games are done.
  final List<String> placements;

  bool get isNew => id.isEmpty;
  bool get isFull => seeds.length >= maxTeams;

  DivisionSummary get summary =>
      DivisionSummary(id: id, division: division, level: level);

  String get label => summary.label;

  /// Seed number of [teamId], 1-based; null if it isn't seeded.
  int? seedOf(String teamId) {
    final i = seeds.indexOf(teamId);
    return i < 0 ? null : i + 1;
  }

  /// Every uid who reports scores for some team.
  Set<String> get captainIds => {for (final c in captains.values) ...c};

  TournamentDivision copyWith({
    String? id,
    Division? division,
    CompetitionLevel? level,
    TournamentSettings? settings,
    int? maxTeams,
    List<String>? seeds,
    Map<String, List<String>>? captains,
    List<String>? placements,
    int? Function()? minRoster,
    List<TournamentTeam>? teams,
  }) => TournamentDivision(
    id: id ?? this.id,
    division: division ?? this.division,
    level: level ?? this.level,
    settings: settings ?? this.settings,
    maxTeams: maxTeams ?? this.maxTeams,
    seeds: seeds ?? this.seeds,
    captains: captains ?? this.captains,
    placements: placements ?? this.placements,
    minRoster: minRoster != null ? minRoster() : this.minRoster,
    teams: teams ?? this.teams,
  );

  /// Moves the team at seed index [from] to [to] (0-based, as
  /// ReorderableListView reports them after adjusting for the removal).
  TournamentDivision reseed(int from, int to) {
    final list = [...seeds];
    final team = list.removeAt(from);
    list.insert(to.clamp(0, list.length), team);
    return copyWith(seeds: list);
  }

  factory TournamentDivision.fromMap(String id, Map<String, dynamic> map) =>
      TournamentDivision(
        id: id,
        division: enumByName(Division.values, map['division'], Division.mixed),
        level: enumByName(
          CompetitionLevel.values,
          map['level'],
          CompetitionLevel.club,
        ),
        settings: TournamentSettings.fromMap(
          Map<String, dynamic>.from((map['settings'] as Map?) ?? const {}),
        ),
        maxTeams: (map['maxTeams'] as num?)?.toInt() ?? 16,
        seeds: [for (final s in (map['seeds'] as List?) ?? const []) '$s'],
        captains: {
          for (final e in ((map['captains'] as Map?) ?? const {}).entries)
            '${e.key}': [for (final u in (e.value as List?) ?? const []) '$u'],
        },
        placements: [
          for (final p in (map['placements'] as List?) ?? const []) '$p',
        ],
        minRoster: (map['minRoster'] as num?)?.toInt(),
        teams: [
          for (final t in (map['teams'] as List?) ?? const [])
            if (t is Map) TournamentTeam.fromMap(Map<String, dynamic>.from(t)),
        ],
      );

  Map<String, dynamic> toMap() => {
    'division': division.name,
    'level': level.name,
    'settings': settings.toMap(),
    'maxTeams': maxTeams,
    'seeds': seeds,
    'captains': captains,
    'placements': placements,
    'minRoster': minRoster,
    'teams': [for (final t in teams) t.toMap()],
  };
}

/// Where a team's entry stands.
enum EntryStatus {
  /// The host invited the team; its admins haven't answered.
  invited('Invited'),

  /// The team asked to play; the host hasn't decided.
  applied('Applied'),
  accepted('Accepted'),
  waitlisted('Waitlist'),
  declined('Declined'),

  /// The team pulled out.
  withdrawn('Withdrawn');

  const EntryStatus(this.label);
  final String label;

  /// Still in the running for a spot.
  bool get isActive => this == invited || this == applied || this == waitlisted;
}

/// A team's entry, at `tournaments/{id}/entries/{teamId}`.
class TournamentEntry {
  const TournamentEntry({
    required this.teamId,
    required this.teamName,
    required this.divisionId,
    this.status = EntryStatus.applied,
    this.captainIds = const [],
    this.updatedAt,
  });

  static const maxCaptains = 4;

  final String teamId;
  final String teamName;
  final String divisionId;
  final EntryStatus status;

  /// Who reports scores for the team, picked by its admins.
  final List<String> captainIds;
  final DateTime? updatedAt;

  TournamentEntry copyWith({
    String? divisionId,
    EntryStatus? status,
    List<String>? captainIds,
  }) => TournamentEntry(
    teamId: teamId,
    teamName: teamName,
    divisionId: divisionId ?? this.divisionId,
    status: status ?? this.status,
    captainIds: captainIds ?? this.captainIds,
    updatedAt: updatedAt,
  );

  factory TournamentEntry.fromMap(String teamId, Map<String, dynamic> map) =>
      TournamentEntry(
        teamId: teamId,
        teamName: map['teamName'] as String? ?? '',
        divisionId: map['divisionId'] as String? ?? '',
        status: enumByName(
          EntryStatus.values,
          map['status'],
          EntryStatus.applied,
        ),
        captainIds: [
          for (final u in (map['captainIds'] as List?) ?? const []) '$u',
        ],
        updatedAt: parseDate(map['updatedAt']),
      );

  /// Everything but `updatedAt`, which the repository stamps.
  Map<String, dynamic> toMap() => {
    'teamName': teamName,
    'divisionId': divisionId,
    'status': status.name,
    'captainIds': captainIds,
  };
}

/// Whether a team has paid its bid fee, at
/// `tournaments/{id}/payments/{teamId}`. Only the host's managers and the
/// team's admins can see it.
class EntryPayment {
  const EntryPayment({
    required this.teamId,
    this.paid = false,
    this.paidAt,
    this.note = '',
  });

  static const maxNoteLength = 200;

  final String teamId;
  final bool paid;
  final DateTime? paidAt;

  /// The host's own note, e.g. "Venmo 3/2".
  final String note;

  factory EntryPayment.fromMap(String teamId, Map<String, dynamic> map) =>
      EntryPayment(
        teamId: teamId,
        paid: map['paid'] as bool? ?? false,
        paidAt: parseDate(map['paidAt']),
        note: map['note'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
    'paid': paid,
    'paidAt': paidAt,
    'note': note,
  };
}

/// Where a player's signup stands (player entry).
enum SignupStatus {
  applied('Signed up'),
  accepted('Accepted'),
  waitlisted('Waitlist'),
  declined('Declined'),
  withdrawn('Withdrawn');

  const SignupStatus(this.label);
  final String label;

  bool get isActive => this == applied || this == waitlisted;
}

/// Who a player is matched against in mixed divisions: the usual
/// "gender match" labels used for line calls.
enum GenderMatch {
  mmp('MMP'),
  wmp('WMP');

  const GenderMatch(this.label);
  final String label;
}

/// A player's signup for a player-entry tournament or league, at
/// `tournaments/{id}/signups/{uid}`. Skill and gender are private: only the
/// host's managers and the player can read it. Whether they've paid lives
/// in `payments/{uid}`, which only the host writes.
class PlayerSignup {
  const PlayerSignup({
    required this.uid,
    required this.name,
    required this.divisionId,
    this.skill = 3,
    this.gender,
    this.status = SignupStatus.applied,
    this.createdAt,
    this.updatedAt,
  });

  static const minSkill = 1;
  static const maxSkill = 5;

  final String uid;
  final String name;
  final String divisionId;

  /// Self-rated, 1 (new) to 5 (very experienced).
  final int skill;

  /// Mixed divisions only; null otherwise.
  final GenderMatch? gender;
  final SignupStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  PlayerSignup copyWith({
    String? name,
    String? divisionId,
    int? skill,
    GenderMatch? Function()? gender,
    SignupStatus? status,
  }) => PlayerSignup(
    uid: uid,
    name: name ?? this.name,
    divisionId: divisionId ?? this.divisionId,
    skill: skill ?? this.skill,
    gender: gender != null ? gender() : this.gender,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  factory PlayerSignup.fromMap(String uid, Map<String, dynamic> map) =>
      PlayerSignup(
        uid: uid,
        name: map['name'] as String? ?? '',
        divisionId: map['divisionId'] as String? ?? '',
        skill: ((map['skill'] as num?)?.toInt() ?? 3).clamp(minSkill, maxSkill),
        gender: switch (map['gender']) {
          'mmp' => GenderMatch.mmp,
          'wmp' => GenderMatch.wmp,
          _ => null,
        },
        status: enumByName(
          SignupStatus.values,
          map['status'],
          SignupStatus.applied,
        ),
        createdAt: parseDate(map['createdAt']),
        updatedAt: parseDate(map['updatedAt']),
      );

  /// Everything but createdAt/updatedAt, which the repository stamps.
  Map<String, dynamic> toMap() => {
    'name': name,
    'divisionId': divisionId,
    'skill': skill,
    'gender': gender?.name,
    'status': status.name,
  };
}

/// A hosted tournament a team has entered, from the team's side
/// (`teams/{teamId}/tournamentEntries/{tournamentId}`, kept by the server):
/// what its Tournaments tab lists under "Playing in".
class EnteredTournament {
  const EnteredTournament({
    required this.tournamentId,
    required this.name,
    required this.status,
    this.hostName = '',
    this.startsOn,
    this.endsOn,
    this.location = '',
  });

  final String tournamentId;
  final String name;
  final String hostName;
  final DateTime? startsOn;
  final DateTime? endsOn;
  final String location;
  final EntryStatus status;

  /// Still in it, or waiting to hear: not declined or withdrawn.
  bool get isCurrent => status == EntryStatus.accepted || status.isActive;

  factory EnteredTournament.fromMap(String id, Map<String, dynamic> map) =>
      EnteredTournament(
        tournamentId: id,
        name: map['name'] as String? ?? 'Tournament',
        hostName: map['hostName'] as String? ?? '',
        startsOn: parseDate(map['startsOn']),
        endsOn: parseDate(map['endsOn']),
        location: map['location'] as String? ?? '',
        status: enumByName(
          EntryStatus.values,
          map['status'],
          EntryStatus.applied,
        ),
      );
}

/// Soonest first; undated ones last.
List<EnteredTournament> sortEntered(List<EnteredTournament> list) =>
    list..sort((a, b) {
      final x = a.startsOn;
      final y = b.startsOn;
      if (x == null || y == null) return x == null ? (y == null ? 0 : 1) : -1;
      return x.compareTo(y);
    });
