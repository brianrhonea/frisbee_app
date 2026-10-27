import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../domain/models/app_user.dart';
import '../../../utils/command.dart';

class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel({required AuthRepository authRepository})
    : _auth = authRepository {
    updateDisplayName = Command1<void, String>(_auth.updateDisplayName);
    signOut = Command0<void>(_auth.signOut);
    deleteAccount = Command0<void>(_auth.deleteAccount);
    _auth.addListener(notifyListeners);
  }

  final AuthRepository _auth;

  AppUser? get user => _auth.currentUser;

  late final Command1<void, String> updateDisplayName;
  late final Command0<void> signOut;
  late final Command0<void> deleteAccount;

  @override
  void dispose() {
    _auth.removeListener(notifyListeners);
    super.dispose();
  }
}
