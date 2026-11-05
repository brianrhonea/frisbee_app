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

  /// False until the initial auth state has been resolved, and for a
  /// signed-in user, until we know whether they have a username.
  bool get isReady;

  /// Signed in without a username yet (e.g. new with Google or Apple): the
  /// app asks for one before anything else.
  bool get needsUsername;

  /// Whether nobody has [username] yet. It's only claimed by
  /// [claimUsername], so it can still be taken in between.
  Future<Result<bool>> isUsernameAvailable(String username);

  /// Gives the signed-in user [username], once; fails if it's taken.
  Future<Result<void>> claimUsername(String username);

  Future<Result<void>> signInWithEmail(String email, String password);

  /// Signs in with an email or a username (with or without "@") and the
  /// account's password. A username fails just like a wrong password if
  /// nobody has it.
  Future<Result<void>> signIn(String emailOrUsername, String password);

  /// Creates an email account named "[firstName] [lastName]" and claims
  /// [username] for it. If the username was taken in the meantime, the
  /// account is still made and the app asks for another
  /// ([needsUsername]).
  Future<Result<void>> signUpWithEmail({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String username,
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

  /// For accounts with a password: checks [current], then sets [next]
  /// (already checked against the password policy).
  Future<Result<void>> changePassword({
    required String current,
    required String next,
  });

  /// Deletes the account and everything the user created, then signs out.
  /// Needs a recent [reauthenticate]. Sets [signedOutNotice].
  Future<Result<void>> deleteAccount();

  /// A message for the sign-in page about why the user was signed out,
  /// e.g. after deleting their account. Shown once.
  String? get signedOutNotice;

  void clearSignedOutNotice();
}
