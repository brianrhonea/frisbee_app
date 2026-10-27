import 'package:flutter/foundation.dart';

import '../../../domain/models/app_user.dart';
import '../../../utils/result.dart';

/// Source of truth for the signed-in user.
///
/// Extends [ChangeNotifier] so the router can refresh on auth changes.
abstract class AuthRepository extends ChangeNotifier {
  /// Null when signed out.
  AppUser? get currentUser;

  bool get isAuthenticated => currentUser != null;

  /// False until the initial auth state has been resolved.
  bool get isReady;

  Future<Result<void>> signInWithEmail(String email, String password);

  Future<Result<void>> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  });

  Future<Result<void>> signInWithGoogle();

  Future<Result<void>> signInWithApple();

  Future<Result<void>> sendPasswordReset(String email);

  Future<Result<void>> updateDisplayName(String name);

  Future<Result<void>> signOut();

  Future<Result<void>> deleteAccount();
}
