import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/team/view_as_team_repository.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';

class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel({required AuthRepository authRepository, ViewAsRole? viewAs})
    : _auth = authRepository,
      _viewAs = viewAs {
    updateDisplayName = Command1<void, String>(_auth.updateDisplayName);
    signOut = Command0<void>(_auth.signOut);
    deleteAccount = Command0<void>(_auth.deleteAccount);
    _auth.addListener(notifyListeners);
    _viewAs?.addListener(notifyListeners);
  }

  final AuthRepository _auth;

  /// Present in debug builds only.
  final ViewAsRole? _viewAs;

  /// Whether the developer "view as role" option is available.
  bool get canViewAs => _viewAs != null;

  /// Role previewed on every team, or null for the user's real roles.
  TeamRole? get viewAsRole => _viewAs?.role;

  void setViewAsRole(TeamRole? role) => _viewAs?.role = role;

  AppUser? get user => _auth.currentUser;

  late final Command1<void, String> updateDisplayName;
  late final Command0<void> signOut;
  late final Command0<void> deleteAccount;

  @override
  void dispose() {
    _auth.removeListener(notifyListeners);
    _viewAs?.removeListener(notifyListeners);
    super.dispose();
  }
}
