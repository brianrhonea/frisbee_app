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

  /// How the user confirms it's them before deleting their account; null
  /// when signed out.
  SignInMethod? get reauthMethod;

  /// Signs the user in again; [password] for [SignInMethod.password].
  Future<Result<void>> reauthenticate({String? password});

  /// Deletes the account and everything the user created, then signs out.
  /// Needs a recent [reauthenticate]. Sets [signedOutNotice].
  Future<Result<void>> deleteAccount();

  /// A message for the sign-in page about why the user was signed out,
  /// e.g. after deleting their account. Shown once.
  String? get signedOutNotice;

  void clearSignedOutNotice();
}
