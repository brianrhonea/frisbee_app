import 'package:flutter/foundation.dart';

import '../../../data/repositories/agreement/agreement_repository.dart';
import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/personal/personal_repository.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// "Couldn't check your account": shown instead of the app when the sign-up
/// checks (the terms agreement and the personal-details status) errored or
/// answered with something unreadable. The router keeps the member here
/// until a retry gets a proper answer, so a bad answer never lets anyone
/// skip a required step.
class AccountCheckViewModel extends ChangeNotifier {
  AccountCheckViewModel({
    required AgreementRepository agreementRepository,
    required PersonalDetailsRepository personalRepository,
    required AuthRepository authRepository,
  }) : _agreements = agreementRepository,
       _personal = personalRepository {
    retry = Command0<void>(_retry);
    signOut = Command0<void>(authRepository.signOut);
  }

  final AgreementRepository _agreements;
  final PersonalDetailsRepository _personal;

  bool _retriedAndFailed = false;

  /// A retry has run and the check still fails.
  bool get retriedAndFailed => _retriedAndFailed;

  /// Asks again. When the answers are fine the router leaves this screen.
  late final Command0<void> retry;

  late final Command0<void> signOut;

  Future<Result<void>> _retry() async {
    _retriedAndFailed = false;
    notifyListeners();
    // Only the check that failed is asked again.
    await Future.wait([
      if (_agreements.checkFailed) _agreements.refresh(),
      if (_personal.checkFailed) _personal.refreshStatus(),
    ]);
    _retriedAndFailed = _agreements.checkFailed || _personal.checkFailed;
    notifyListeners();
    return const Result.ok(null);
  }
}
