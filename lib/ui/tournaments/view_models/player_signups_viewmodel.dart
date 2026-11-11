import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/hosted_tournament/hosted_tournament_repository.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// What a player says when they sign up.
typedef SignupAnswers = ({String divisionId, int skill, GenderMatch? gender});

typedef SignupDecision = ({String uid, SignupStatus status});

/// Players signing up for a player-entry tournament or league, from both
/// sides: a player signs up, edits their answers and withdraws, and the
/// host's managers accept, waitlist or decline them and mark each paid.
///
/// Skill and gender are private, so only managers read every signup;
/// everyone else sees just their own and their own payment. The page
/// tells this view model whether the user manages the host through
/// [setManager], since the host loads after the tournament.
class PlayerSignupsViewModel extends ChangeNotifier {
  PlayerSignupsViewModel({
    required this.tournamentId,
    required HostedTournamentRepository tournamentRepository,
    required AuthRepository authRepository,
    bool manager = false,
  }) : _repo = tournamentRepository,
       _auth = authRepository,
       _uid = authRepository.currentUser?.uid ?? '' {
    signUp = Command1<void, SignupAnswers>(_signUp);
    withdraw = Command0<void>(_withdraw);
    decide = Command1<void, SignupDecision>(_decide);
    setPaid = Command1<void, ({String uid, bool paid})>(_setPaid);
    if (_uid.isNotEmpty) {
      _subs = [
        _repo.watchSignup(tournamentId, _uid).listen((s) {
          _mine = s;
          notifyListeners();
        }, onError: (Object _) {}),
        _repo.watchPayment(tournamentId, _uid).listen((p) {
          _myPayment = p;
          notifyListeners();
        }, onError: (Object _) {}),
      ];
    }
    setManager(manager);
  }

  final String tournamentId;
  final HostedTournamentRepository _repo;
  final AuthRepository _auth;
  final String _uid;
  List<StreamSubscription<Object?>> _subs = const [];
  StreamSubscription<List<PlayerSignup>>? _signupsSub;
  StreamSubscription<List<EntryPayment>>? _paymentsSub;

  bool _manager = false;
  PlayerSignup? _mine;
  EntryPayment? _myPayment;
  List<PlayerSignup> _signups = const [];
  Map<String, EntryPayment> _payments = const {};

  late final Command1<void, SignupAnswers> signUp;
  late final Command0<void> withdraw;
  late final Command1<void, SignupDecision> decide;
  late final Command1<void, ({String uid, bool paid})> setPaid;

  List<Command<void>> get commands => [signUp, withdraw, decide, setPaid];

  String get uid => _uid;
  bool get isManager => _manager;

  /// This user's own signup; null if they haven't signed up (or withdrew
  /// and it was deleted).
  PlayerSignup? get mine => _mine;

  /// Signed up and still in the running, or already in.
  bool get isSignedUp =>
      _mine != null && _mine!.status != SignupStatus.withdrawn;

  /// Everyone who signed up (managers only), by name.
  List<PlayerSignup> get signups => _signups;

  List<PlayerSignup> signupsIn(String divisionId) => [
    for (final s in _signups)
      if (s.divisionId == divisionId) s,
  ];

  /// Accepted players in a division: who gets drafted onto a team.
  List<PlayerSignup> acceptedIn(String divisionId) => [
    for (final s in signupsIn(divisionId))
      if (s.status == SignupStatus.accepted) s,
  ];

  /// Managers start and stop reading everyone's signups and payments.
  void setManager(bool manager) {
    if (manager == _manager && (_signupsSub != null || !manager)) return;
    _manager = manager;
    _signupsSub?.cancel();
    _paymentsSub?.cancel();
    _signupsSub = _paymentsSub = null;
    if (manager) {
      _signupsSub = _repo.watchSignups(tournamentId).listen((s) {
        _signups = s;
        notifyListeners();
      }, onError: (Object _) {});
      _paymentsSub = _repo.watchPayments(tournamentId).listen((p) {
        _payments = {for (final x in p) x.teamId: x};
        notifyListeners();
      }, onError: (Object _) {});
    } else {
      _signups = const [];
      _payments = const {};
    }
    notifyListeners();
  }

  // ---- Fees ---------------------------------------------------------------

  /// Whether [uid] is marked paid. A player sees their own.
  bool isPaid(String uid) => uid == _uid && !_manager
      ? _myPayment?.paid ?? false
      : _payments[uid]?.paid ?? false;

  EntryPayment? paymentOf(String uid) =>
      uid == _uid && !_manager ? _myPayment : _payments[uid];

  /// Whether [uid]'s fee is past due on [fee] and still unpaid.
  bool isOverdue(String uid, EntryFee? fee, DateTime now) {
    final due = fee?.dueAt;
    final owes = fee != null && fee.amountCents > 0;
    return owes && due != null && now.isAfter(due) && !isPaid(uid);
  }

  /// Accepted or waiting players who haven't paid (managers).
  int unpaidCount(EntryFee? fee) {
    if (fee == null || fee.amountCents == 0) return 0;
    return [
      for (final s in _signups)
        if ((s.status == SignupStatus.accepted ||
                s.status == SignupStatus.applied) &&
            !isPaid(s.uid))
          s,
    ].length;
  }

  // ---- Actions ------------------------------------------------------------

  Future<Result<void>> _signUp(SignupAnswers a) async {
    final me = _auth.currentUser;
    if (me == null) return Result.error(Exception('Sign in to sign up.'));
    if (a.divisionId.isEmpty) {
      return Result.error(Exception('Pick a division.'));
    }
    if (a.skill < PlayerSignup.minSkill || a.skill > PlayerSignup.maxSkill) {
      return Result.error(Exception('Rate your skill from 1 to 5.'));
    }
    // The name is copied onto teams anyone signed in can read, so never
    // their email.
    final name = switch ((me.displayName, me.username)) {
      (final n?, _) when n.trim().isNotEmpty => n.trim(),
      (_, final u?) when u.trim().isNotEmpty => u.trim(),
      _ => 'Player',
    };
    // Keep their place if they're editing (or coming back).
    final before = _mine;
    final keep = before != null && before.status != SignupStatus.withdrawn;
    return _repo.saveSignup(
      tournamentId,
      PlayerSignup(
        uid: me.uid,
        name: name,
        divisionId: a.divisionId,
        skill: a.skill,
        gender: a.gender,
        status: keep ? before.status : SignupStatus.applied,
      ),
    );
  }

  Future<Result<void>> _withdraw() async {
    if (_uid.isEmpty) return Result.error(Exception('Sign in first.'));
    return _repo.setSignupStatus(tournamentId, _uid, SignupStatus.withdrawn);
  }

  Future<Result<void>> _decide(SignupDecision d) async {
    if (!_manager) {
      return Result.error(Exception('Only the host can do that.'));
    }
    return _repo.setSignupStatus(tournamentId, d.uid, d.status);
  }

  Future<Result<void>> _setPaid(({String uid, bool paid}) p) async {
    if (!_manager) {
      return Result.error(Exception('Only the host can do that.'));
    }
    final old = _payments[p.uid];
    return _repo.savePayment(
      tournamentId,
      EntryPayment(
        teamId: p.uid,
        paid: p.paid,
        paidAt: p.paid ? DateTime.now() : null,
        note: old?.note ?? '',
      ),
    );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _signupsSub?.cancel();
    _paymentsSub?.cancel();
    super.dispose();
  }
}
