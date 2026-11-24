import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/profile/profile_repository.dart';
import '../../../domain/models/player_profile.dart';
import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/hosted_tournament/hosted_tournament_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/group_tournament.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Hosting a tournament or a league, or editing its details: name, dates,
/// place, who can play and the fee, for a league its season, the one format
/// every division plays, and which divisions are open (checkboxes).
///
/// A new event is a tournament or a league, and teams apply to it or
/// individual players sign up (a hat tournament is a tournament that takes
/// players). That's fixed once it's created; everything else can change.
class HostedTournamentFormViewModel extends ChangeNotifier {
  HostedTournamentFormViewModel({
    this.hostId,
    this.tournamentId,
    required HostedTournamentRepository tournamentRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
    ProfileRepository? profileRepository,
    DateTime Function()? now,
    HostedType? type,
  }) : assert(hostId != null || tournamentId != null),
       _repo = tournamentRepository,
       _teams = teamRepository,
       _auth = authRepository,
       _profiles = profileRepository {
    final today = (now ?? DateTime.now)();
    // A month out on a Saturday, like most club events.
    var start = DateTime(today.year, today.month, today.day + 30);
    while (start.weekday != DateTime.saturday) {
      start = start.add(const Duration(days: 1));
    }
    _startsOn = start;
    _endsOn = start.add(const Duration(days: 1));
    _format = EventFormat.usual(_draft);
    save = Command0<String>(_save);
    publish = Command0<String>(_publish);
    final id = tournamentId;
    if (id == null) {
      _watchHost(hostId!);
      _loaded = true;
      // Started from "Host a league" (or a hat tournament).
      if (type == HostedType.league) setKind(HostedKind.league);
      if (type == HostedType.hat) setEntryType(TournamentEntryType.players);
    } else {
      _tournamentSub = _repo.watchTournament(id).listen((t) {
        if (t != null && _existing == null) _fill(t);
        _existing = t;
        _loaded = true;
        if (t != null && _hostSub == null) _watchHost(t.hostId);
        notifyListeners();
      }, onError: _onError);
      _divisionsSub = _repo.watchDivisions(id).listen((l) {
        final first = _divisions == null;
        _divisions = l;
        if (first) {
          _wanted = {for (final d in l) d.division};
          // Older events kept a format on each division.
          if (_existing?.format == null && l.isNotEmpty) {
            _format = EventFormat.of(l.first);
          }
        }
        notifyListeners();
      }, onError: _onError);
      // Only managers read these; a division someone has signed up for
      // or entered stays open.
      _entriesSub = _repo.watchEntries(id).listen((l) {
        _entries = l;
        _syncTaken();
      }, onError: (Object _) {});
      _signupsSub = _repo.watchSignups(id).listen((l) {
        _signups = l;
        _syncTaken();
      }, onError: (Object _) {});
    }
  }

  final String? hostId;
  final String? tournamentId;
  final HostedTournamentRepository _repo;
  final TeamRepository _teams;
  final AuthRepository _auth;
  final ProfileRepository? _profiles;

  /// Whether the Director step can search members.
  bool get canSearchPeople => _profiles != null;

  /// Stall 10 members matching [query], for the Director step.
  Future<List<PlayerProfile>> searchPeople(String query) async {
    final repo = _profiles;
    if (repo == null || query.trim().length < 2) return const [];
    return switch (await repo.searchPlayers(query.trim())) {
      Ok(:final value) => value,
      Error() => const [],
    };
  }

  StreamSubscription<Team?>? _hostSub;
  StreamSubscription<HostedTournament?>? _tournamentSub;
  StreamSubscription<List<TournamentDivision>>? _divisionsSub;
  StreamSubscription<List<TournamentEntry>>? _entriesSub;
  StreamSubscription<List<PlayerSignup>>? _signupsSub;

  /// Division ids with teams or players in them that haven't withdrawn.
  Set<String> _taken = {};
  List<TournamentEntry> _entries = const [];
  List<PlayerSignup> _signups = const [];

  void _syncTaken() {
    _taken = {
      for (final e in _entries)
        if (e.status != EntryStatus.withdrawn &&
            e.status != EntryStatus.declined)
          e.divisionId,
      for (final s in _signups)
        if (s.status != SignupStatus.withdrawn &&
            s.status != SignupStatus.declined)
          s.divisionId,
    };
    notifyListeners();
  }

  /// Saves it (a new event as a draft only the host's managers see).
  late final Command0<String> save;

  /// Saves it and publishes it: a draft opens registration, as the event
  /// page's "Publish and open registration" does. Only for drafts
  /// ([isDraft]).
  late final Command0<String> publish;

  /// The form's steps, in order; the last is Review.
  static const steps = [
    'Details',
    'When & where',
    'Who can play',
    'Format & divisions',
    'Fees & deadline',
    'Director',
    'Review',
  ];

  /// Index of the Director step.
  static const directorStep = 5;

  int _step = 0;

  /// The step showing (an index into [steps]).
  int get step => _step;
  bool get onReview => _step == steps.length - 1;

  void goTo(int step) {
    final s = step.clamp(0, steps.length - 1);
    if (s == _step) return;
    _step = s;
    notifyListeners();
  }

  void next() => goTo(_step + 1);
  void back() => goTo(_step - 1);

  /// Still a draft (or not created yet): the form offers Save draft and
  /// Publish. A published event has a single Save, so editing it never
  /// changes where it stands.
  bool get isDraft =>
      isNew || (_existing?.status ?? HostedStatus.draft) == HostedStatus.draft;

  /// The new event Publish created but couldn't publish, so the screen
  /// opens it as a draft instead of creating it again.
  String? get createdDraftId => _createdDraftId;
  String? _createdDraftId;

  /// The existing event's divisions, once loaded.
  List<TournamentDivision>? _divisions;
  Set<Division> _wanted = {Division.mixed};
  late EventFormat _format;

  Team? _host;
  HostedTournament? _existing;
  bool _loaded = false;
  Object? _error;

  String name = '';
  String description = '';
  String location = '';
  late DateTime _startsOn;
  DateTime? _endsOn;
  TournamentVisibility visibility = TournamentVisibility.public;

  /// Days before the start invited teams answer by, or null for none.
  int? inviteReplyDays = HostedTournament.defaultInviteReplyDays;
  bool _hasFee = false;
  String feeAmount = '';
  String currency = 'USD';
  String feeInstructions = '';

  /// The entry deadline: rosters and fees are due (the fee's due date).
  DateTime? _feeDue;
  bool _payerCoversFees = false;

  /// The tournament director, or null for none (a contact; no rights).
  TournamentDirector? _director;
  HostedKind _kind = HostedKind.tournament;
  TournamentEntryType _entryType = TournamentEntryType.teams;
  DraftMode draftMode = DraftMode.balanced;
  LeagueSeason _season = const LeagueSeason();
  bool _teamEntry = false;

  /// What a team pays to reserve a spot, as typed.
  String teamFeeAmount = '';

  bool get loaded => _loaded || _error != null;
  Object? get error => _error;
  bool get isNew => tournamentId == null;
  Team? get host => _host;
  HostedTournament? get existing => _existing;
  DateTime get startsOn => _startsOn;
  DateTime? get endsOn => _endsOn;
  bool get hasFee => _hasFee;
  DateTime? get feeDue => _feeDue;

  /// When rosters and fees are due (the same as [feeDue]).
  DateTime? get entryDeadline => _feeDue;

  TournamentDirector? get director => _director;

  void setDirector(TournamentDirector? d) {
    _director = d;
    notifyListeners();
  }

  /// The signed-in member, for "It's me" on the Director step.
  String? get myUid => _auth.currentUser?.uid;
  /// Their name on the host, else their account's (the website's
  /// DirectorStep); empty when neither is known.
  String get myName {
    final uid = myUid;
    final onHost = uid == null ? null : _host?.memberNames[uid];
    return (onHost ?? _auth.currentUser?.displayName ?? '').trim();
  }

  /// Paid online, payers also pay the processing fees so the host gets the
  /// whole fee.
  bool get payerCoversFees => _payerCoversFees;

  void setPayerCoversFees(bool v) {
    _payerCoversFees = v;
    notifyListeners();
  }

  HostedKind get kind => _kind;
  TournamentEntryType get entryType => _entryType;
  LeagueSeason get season => _season;
  bool get isLeague => _kind == HostedKind.league;
  bool get takesPlayers => _entryType == TournamentEntryType.players;

  /// What every division plays.
  EventFormat get format => _format;
  TournamentSettings get settings => _format.settings;

  void setFormat(EventFormat f) {
    _format = f;
    notifyListeners();
  }

  void setSettings(TournamentSettings s) =>
      setFormat(_format.copyWith(settings: s));

  /// A new field size also moves the roster minimum when it was still the
  /// usual one for the old size, so a 4v4 league asks for 4.
  void setFieldSize(int n) {
    final usual =
        _format.minRoster == null ||
        _format.minRoster == settings.playersOnField;
    setFormat(
      _format.copyWith(
        settings: settings.copyWith(playersOnField: n),
        minRoster: usual ? () => n : null,
      ),
    );
  }

  /// When the first game starts each day or night.
  void setFirstGame(int hour, int minute) {
    final s = settings.startsAt;
    setSettings(
      settings.copyWith(
        startsAt: DateTime(s.year, s.month, s.day, hour, minute),
      ),
    );
  }

  /// The divisions that will be open.
  Set<Division> get divisions => _wanted;

  bool isOpen(Division d) => _wanted.contains(d);

  /// Why [d] can't be closed: it already has teams or players.
  String? lockedReason(Division d) {
    final existing = _divisions?.where((x) => x.division == d).firstOrNull;
    if (existing == null) return null;
    if (existing.seeds.isNotEmpty || existing.teams.isNotEmpty) {
      return 'It has teams. Remove them on the event page first.';
    }
    if (_taken.contains(existing.id)) {
      return 'People have signed up for it.';
    }
    return null;
  }

  void setOpen(Division d, bool open) {
    if (!open && lockedReason(d) != null) return;
    _wanted = open ? {..._wanted, d} : ({..._wanted}..remove(d));
    notifyListeners();
  }

  /// Whether divisions still take format changes: their schedules aren't
  /// out yet.
  bool get formatEditable {
    final s = _existing?.status ?? HostedStatus.draft;
    return s.index < HostedStatus.scheduled.index;
  }

  /// This event as it stands in the form, for working out its format.
  HostedTournament get _draft => HostedTournament(
    id: '',
    hostId: hostId ?? '',
    hostName: '',
    name: name,
    startsOn: _startsOn,
    endsOn: _endsOn,
    kind: _kind,
    entryType: _entryType,
    season: isLeague ? _season : null,
  );

  /// The fee is per player when players sign up, per team otherwise.
  String get feeName => takesPlayers ? 'Entry fee' : 'Bid fee';

  /// Players sign up, and teams can also reserve a whole spot.
  bool get teamEntry => takesPlayers && _teamEntry;

  /// Teams enter (so they can be invited, and answer by a reply-by time).
  bool get takesTeams => !takesPlayers || teamEntry;

  void setTeamEntry(bool v) {
    _teamEntry = v;
    notifyListeners();
  }

  /// The team spot fee in cents, or null when it isn't a valid amount.
  int? get teamFeeCents => _cents(teamFeeAmount);

  /// Only members of the host with Manage events may host.
  bool get canHost {
    final uid = _auth.currentUser?.uid;
    return uid != null &&
        (_host?.has(uid, TeamPermission.manageEvents) ?? false);
  }

  void _onError(Object e) {
    _error = e;
    notifyListeners();
  }

  void _watchHost(String id) {
    _hostSub = _teams.watchTeam(id).listen((t) {
      _host = t;
      notifyListeners();
    }, onError: _onError);
  }

  void _fill(HostedTournament t) {
    name = t.name;
    description = t.description;
    location = t.location;
    _startsOn = t.startsOn;
    _endsOn = t.endsOn;
    visibility = t.visibility;
    inviteReplyDays = t.inviteReplyDays;
    _kind = t.kind;
    _entryType = t.entryType;
    draftMode = t.draftMode;
    _director = t.director;
    _feeDue = t.entryDeadline;
    _teamEntry = t.teamEntry;
    if (t.teamFee case final f?) {
      teamFeeAmount = (f.amountCents / 100).toStringAsFixed(
        f.amountCents % 100 == 0 ? 0 : 2,
      );
    }
    _season = t.season ?? const LeagueSeason();
    if (t.format case final f?) _format = f;
    final fee = t.bidFee;
    _hasFee = fee != null;
    if (fee != null) {
      feeAmount = (fee.amountCents / 100).toStringAsFixed(
        fee.amountCents % 100 == 0 ? 0 : 2,
      );
      currency = fee.currency;
      feeInstructions = fee.instructions;
      _feeDue = t.entryDeadline ?? fee.dueAt;
      _payerCoversFees = fee.payerCoversFees;
    }
  }

  void setDates(DateTime start, DateTime end) {
    _startsOn = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    _endsOn = last == _startsOn ? null : last;
    notifyListeners();
  }

  /// A league's first night; the season's last night follows from its
  /// length.
  void setFirstNight(DateTime night) {
    _startsOn = DateTime(night.year, night.month, night.day);
    _syncSeasonEnd();
    notifyListeners();
  }

  void setKind(HostedKind k) {
    if (!isNew) return;
    _kind = k;
    if (isLeague) {
      _syncSeasonEnd();
    } else {
      _endsOn = _startsOn.add(const Duration(days: 1));
    }
    _format = EventFormat.usual(_draft);
    notifyListeners();
  }

  void setEntryType(TournamentEntryType t) {
    if (!isNew) return;
    _entryType = t;
    notifyListeners();
  }

  /// Who can enter (a league's third choice is teams and players).
  EntryChoice get entryChoice => EntryChoice.of(_kind, _entryType, _teamEntry);
  List<EntryChoice> get entryChoices => EntryChoice.forKind(_kind);

  void setEntryChoice(EntryChoice c) {
    if (!isNew) return;
    _entryType = c.entryType;
    _teamEntry = c.teamEntry;
    notifyListeners();
  }

  void setDraftMode(DraftMode m) {
    draftMode = m;
    notifyListeners();
  }

  void setSeason(LeagueSeason s) {
    _season = s;
    _syncSeasonEnd();
    notifyListeners();
  }

  /// A league's last night: its first plus a week for each of the season's
  /// weeks, skipped weeks included.
  void _syncSeasonEnd() {
    if (!isLeague) return;
    final nights = _season.weeks + _season.skipDates.length;
    final last = DateTime(
      _startsOn.year,
      _startsOn.month,
      _startsOn.day + 7 * (nights - 1),
    );
    _endsOn = last == _startsOn ? null : last;
  }

  void setVisibility(TournamentVisibility v) {
    visibility = v;
    notifyListeners();
  }

  void setInviteReplyDays(int? days) {
    inviteReplyDays = days;
    notifyListeners();
  }

  void setHasFee(bool v) {
    _hasFee = v;
    notifyListeners();
  }

  void setFeeDue(DateTime? d) {
    _feeDue = d;
    notifyListeners();
  }

  void setCurrency(String c) {
    currency = c;
    notifyListeners();
  }

  /// The fee in cents, or null when [feeAmount] isn't a valid amount.
  int? get feeCents => _cents(feeAmount);

  static int? _cents(String amount) {
    final v = double.tryParse(amount.trim().replaceAll(r'$', ''));
    if (v == null || v < 0 || v > 100000) return null;
    return (v * 100).round();
  }

  String? get problem {
    if (name.trim().isEmpty) return 'Give it a name.';
    if (_hasFee && feeCents == null) {
      return 'Enter the ${feeName.toLowerCase()}, e.g. 250.';
    }
    if (_hasFee && teamEntry && teamFeeCents == null) {
      return 'Enter the team spot fee, e.g. 300.';
    }
    if (HostedTournament.deadlineProblem(_feeDue, _startsOn) case final p?) {
      return p;
    }
    if (_director?.problem case final p?) return p;
    if (_wanted.isEmpty) return 'Open at least one division.';
    if (_wanted.length > HostedTournament.maxDivisions) {
      return 'Up to ${HostedTournament.maxDivisions} divisions.';
    }
    if (isLeague && _season.playoffTeams > 0) {
      if (_season.playoffWeeks < 1) {
        return 'Give the playoffs at least one week.';
      }
      if (_season.playoffWeeks >= _season.weeks) {
        return 'Leave at least one week for the regular season.';
      }
    }
    return null;
  }

  Future<Result<String>> _save() async {
    final user = _auth.currentUser;
    final host = _host;
    final why = problem;
    if (why != null) return Result.error(Exception(why));
    if (user == null || host == null || !canHost) {
      return Result.error(
        Exception('Only members who manage events can host tournaments.'),
      );
    }
    final fee = _hasFee
        ? BidFee(
            amountCents: feeCents!,
            currency: currency,
            instructions: feeInstructions.trim(),
            dueAt: _feeDue,
            payerCoversFees: _payerCoversFees,
          )
        : null;
    final base =
        _existing ??
        HostedTournament(
          id: '',
          hostId: host.id,
          hostName: host.name,
          hostKind: host.kind,
          hostOfficial: host.official,
          name: '',
          startsOn: _startsOn,
          kind: _kind,
          entryType: _entryType,
        );
    var t = base.copyWith(
      name: name.trim(),
      hostName: host.name,
      hostOfficial: host.official,
      description: description.trim(),
      location: location.trim(),
      startsOn: _startsOn,
      endsOn: () => _endsOn,
      visibility: visibility,
      bidFee: () => fee,
      teamEntry: teamEntry,
      teamFee: () => fee != null && teamEntry
          ? BidFee(
              amountCents: teamFeeCents!,
              currency: fee.currency,
              instructions: fee.instructions,
              dueAt: fee.dueAt,
              payerCoversFees: fee.payerCoversFees,
            )
          : null,
      season: () => isLeague ? _season : null,
      draftMode: draftMode,
      inviteReplyDays: () => inviteReplyDays,
      entryDeadline: () => _feeDue,
      director: () => _director,
    );
    final format = _format.on(t);
    t = t.copyWith(format: format);
    final saved = await _repo.saveTournament(t, user);
    if (saved case Error(:final error)) return Result.error(error);
    final id = (saved as Ok<String>).value;
    t = (_existing ?? t).copyWith(id: id, format: format);
    final existing = _divisions ?? const <TournamentDivision>[];
    // Close the unticked ones that have nothing in them yet.
    for (final d in existing) {
      if (_wanted.contains(d.division) || lockedReason(d.division) != null) {
        continue;
      }
      final r = await _repo.deleteDivision(t, d.id);
      if (r case Error(:final error)) return Result.error(error);
      t = t.copyWith(
        divisions: [
          for (final s in t.divisions)
            if (s.id != d.id) s,
        ],
      );
    }
    // Open the new ones, and give the rest the format while it can change.
    final changes = [
      if (formatEditable)
        for (final d in existing)
          if (_wanted.contains(d.division)) format.restamp(d),
      for (final g in EventFormat.divisionChoices)
        if (_wanted.contains(g) && !existing.any((d) => d.division == g))
          format.divisionFor(g),
    ];
    if (changes.isNotEmpty) {
      final r = await _repo.saveDivisions(t, changes);
      if (r case Error(:final error)) return Result.error(error);
    }
    return Result.ok(id);
  }

  Future<Result<String>> _publish() async {
    if (!isDraft) return Result.error(Exception('It is already published.'));
    final saved = await _save();
    if (saved case Error(:final error)) return Result.error(error);
    final id = (saved as Ok<String>).value;
    final r = await _repo.setStatus(id, HostedStatus.registration);
    if (r case Error(:final error)) {
      if (isNew) _createdDraftId = id;
      return Result.error(error);
    }
    return Result.ok(id);
  }

  @override
  void dispose() {
    _hostSub?.cancel();
    _tournamentSub?.cancel();
    _divisionsSub?.cancel();
    _entriesSub?.cancel();
    _signupsSub?.cancel();
    super.dispose();
  }
}
