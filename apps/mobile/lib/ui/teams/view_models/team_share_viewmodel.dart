import 'package:flutter/foundation.dart';

import '../../../data/repositories/team_share/team_share_repository.dart';
import '../../../domain/models/team_share.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// A team's fee split (TeamShareCard): each member's share, how to pay the
/// collector, and who has paid. The website's TeamShare does the same.
class TeamShareViewModel extends ChangeNotifier {
  TeamShareViewModel({
    required this.teamId,
    required TeamShareRepository repository,
  }) : _repo = repository {
    load = Command0(_load)..execute();
    save = Command1(_save);
    clear = Command0(_clear);
    markPaid = Command1(_markPaid);
  }

  final String teamId;
  final TeamShareRepository _repo;

  late final Command0<void> load;
  late final Command1<void, ({int amountCents, String note})> save;
  late final Command0<void> clear;
  late final Command1<void, ({String uid, bool paid})> markPaid;

  TeamShareView _view = TeamShareView.none;
  TeamShareView get view => _view;

  TeamShare? get share => _view.share;
  bool get manages => _view.manages;

  ({int paid, int owed, int collectedCents, int outstandingCents}) get totals =>
      shareTotals(share?.amountCents ?? 0, _view.members);

  Result<void> _apply(Result<TeamShareView> r) {
    switch (r) {
      case Ok(:final value):
        _view = value;
        notifyListeners();
        return const Result.ok(null);
      case Error(:final error):
        return Result.error(error);
    }
  }

  Future<Result<void>> _load() async => _apply(await _repo.view(teamId));

  Future<Result<void>> _save(({int amountCents, String note}) s) async =>
      _apply(await _repo.set(teamId, amountCents: s.amountCents, note: s.note));

  Future<Result<void>> _clear() async {
    final r = await _repo.clear(teamId);
    if (r is Ok) {
      _view = TeamShareView(manages: _view.manages);
      notifyListeners();
    }
    return r;
  }

  Future<Result<void>> _markPaid(({String uid, bool paid}) m) async =>
      _apply(await _repo.markPaid(teamId, m.uid, paid: m.paid));
}
