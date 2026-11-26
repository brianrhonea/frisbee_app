import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../domain/models/app_user.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// "Stall 10 is for players 18 and over": the dead end for a birth date
/// under 18 (launch is adults only). Nothing to retry: the only ways out
/// are signing out and deleting the account.
class AdultsOnlyViewModel extends ChangeNotifier {
  AdultsOnlyViewModel({required AuthRepository authRepository})
    : _auth = authRepository {
    signOut = Command0<void>(_auth.signOut);
    deleteAccount = Command1<void, String?>(_delete);
  }

  final AuthRepository _auth;

  late final Command0<void> signOut;

  /// Takes the account's password, or null for Google and Apple accounts.
  late final Command1<void, String?> deleteAccount;

  /// How the person confirms it's them before the account is deleted.
  SignInMethod? get reauthMethod => _auth.reauthMethod;

  Future<Result<void>> _delete(String? password) async {
    final confirmed = await _auth.reauthenticate(password: password);
    if (confirmed is Error<void>) return confirmed;
    return _auth.deleteAccount();
  }

  @override
  void dispose() {
    signOut.dispose();
    deleteAccount.dispose();
    super.dispose();
  }
}
