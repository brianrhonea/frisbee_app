import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/hosted_tournament/hosted_tournament_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Hosting a tournament or a league, or editing its details: name, dates,
/// place, who can play and the fee, and for a league its season. Divisions
/// are set up on its page.
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
    DateTime Function()? now,
  }) : assert(hostId != null || tournamentId != null),
       _repo = tournamentRepository,
       _teams = teamRepository,
       _auth = authRepository {
    final today = (now ?? DateTime.now)();
    // A month out on a Saturday, like most club events.
    var start = DateTime(today.year, today.month, today.day + 30);
    while (start.weekday != DateTime.saturday) {
      start = start.add(const Duration(days: 1));
    }
    _startsOn = start;
    _endsOn = start.add(const Duration(days: 1));
    save = Command0<String>(_save);
    final id = tournamentId;
    if (id == null) {
      _watchHost(hostId!);
      _loaded = true;
    } else {
      _tournamentSub = _repo.watchTournament(id).listen((t) {
        if (t != null && _existing == null) _fill(t);
        _existing = t;
        _loaded = true;
        if (t != null && _hostSub == null) _watchHost(t.hostId);
        notifyListeners();
      }, onError: _onError);
    }
  }

  final String? hostId;
  final String? tournamentId;
  final HostedTournamentRepository _repo;
  final TeamRepository _teams;
  final AuthRepository _auth;
  StreamSubscription<Team?>? _hostSub;
  StreamSubscription<HostedTournament?>? _tournamentSub;

  late final Command0<String> save;

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
  bool _hasFee = false;
  String feeAmount = '';
  String currency = 'USD';
  String feeInstructions = '';
  DateTime? _feeDue;
  HostedKind _kind = HostedKind.tournament;
  TournamentEntryType _entryType = TournamentEntryType.teams;
  DraftMode draftMode = DraftMode.balanced;
  LeagueSeason _season = const LeagueSeason();

  bool get loaded => _loaded || _error != null;
  Object? get error => _error;
  bool get isNew => tournamentId == null;
  Team? get host => _host;
  HostedTournament? get existing => _existing;
  DateTime get startsOn => _startsOn;
  DateTime? get endsOn => _endsOn;
  bool get hasFee => _hasFee;
  DateTime? get feeDue => _feeDue;
  HostedKind get kind => _kind;
  TournamentEntryType get entryType => _entryType;
  LeagueSeason get season => _season;
  bool get isLeague => _kind == HostedKind.league;
  bool get takesPlayers => _entryType == TournamentEntryType.players;

  /// The fee is per player when players sign up, per team otherwise.
  String get feeName => takesPlayers ? 'Entry fee' : 'Bid fee';

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
    _kind = t.kind;
    _entryType = t.entryType;
    draftMode = t.draftMode;
    _season = t.season ?? const LeagueSeason();
    final fee = t.bidFee;
    _hasFee = fee != null;
    if (fee != null) {
      feeAmount = (fee.amountCents / 100).toStringAsFixed(
        fee.amountCents % 100 == 0 ? 0 : 2,
      );
      currency = fee.currency;
      feeInstructions = fee.instructions;
      _feeDue = fee.dueAt;
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
    notifyListeners();
  }

  void setEntryType(TournamentEntryType t) {
    if (!isNew) return;
    _entryType = t;
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
  int? get feeCents {
    final v = double.tryParse(feeAmount.trim().replaceAll(r'$', ''));
    if (v == null || v < 0 || v > 100000) return null;
    return (v * 100).round();
  }

  String? get problem {
    if (name.trim().isEmpty) return 'Give it a name.';
    if (_hasFee && feeCents == null) {
      return 'Enter the ${feeName.toLowerCase()}, e.g. 250.';
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
          )
        : null;
    final base =
        _existing ??
        HostedTournament(
          id: '',
          hostId: host.id,
          hostName: host.name,
          hostKind: host.kind,
          name: '',
          startsOn: _startsOn,
          kind: _kind,
          entryType: _entryType,
        );
    return _repo.saveTournament(
      base.copyWith(
        name: name.trim(),
        hostName: host.name,
        description: description.trim(),
        location: location.trim(),
        startsOn: _startsOn,
        endsOn: () => _endsOn,
        visibility: visibility,
        bidFee: () => fee,
        season: () => isLeague ? _season : null,
        draftMode: draftMode,
      ),
      user,
    );
  }

  @override
  void dispose() {
    _hostSub?.cancel();
    _tournamentSub?.cancel();
    super.dispose();
  }
}
