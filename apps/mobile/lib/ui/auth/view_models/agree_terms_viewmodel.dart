import 'package:flutter/foundation.dart';

import '../../../data/repositories/agreement/agreement_repository.dart';
import '../../../data/repositories/auth/auth_repository.dart';
import '../../../utils/command.dart';

/// "Before you start": read and agree to the Community Guidelines and
/// Terms of Service. New accounts see it during sign-up; existing members
/// once, on their next open (and again when [termsVersion] goes up).
class AgreeTermsViewModel extends ChangeNotifier {
  AgreeTermsViewModel({
    required AgreementRepository agreementRepository,
    required AuthRepository authRepository,
  }) : _agreements = agreementRepository {
    agree = Command0<void>(_agreements.agree);
    signOut = Command0<void>(authRepository.signOut);
  }

  final AgreementRepository _agreements;

  bool _checked = false;

  /// The "I've read and agree" box; Continue waits for it.
  bool get checked => _checked;

  set checked(bool value) {
    if (value == _checked) return;
    _checked = value;
    notifyListeners();
  }

  /// Records the agreement; the router then carries on.
  late final Command0<void> agree;

  late final Command0<void> signOut;
}
