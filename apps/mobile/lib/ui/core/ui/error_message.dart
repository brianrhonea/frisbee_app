import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../domain/models/username.dart';
import '../../../utils/result.dart';

/// Whether [error] (a [Result] error or an exception) is the person closing
/// or cancelling a Google or Apple sign-in. That isn't a failure: callers
/// show nothing (the website ignores the same cases).
bool isSignInCancelled(Object? error) {
  final e = error is Error ? error.error : error;
  return switch (e) {
    GoogleSignInException(code: GoogleSignInExceptionCode.canceled) => true,
    FirebaseAuthException(
      code: 'canceled' ||
          'cancelled' ||
          'popup-closed-by-user' ||
          'cancelled-popup-request' ||
          'user-cancelled' ||
          'web-context-canceled' ||
          'web-context-cancelled',
    ) =>
      true,
    _ => false,
  };
}

/// User-facing text for an error [Result] or exception.
String errorMessage(Object? error) {
  final e = error is Error ? error.error : error;
  return switch (e) {
    UsernameTakenException() => e.toString(),
    FirebaseAuthException(code: 'invalid-credential' || 'wrong-password') =>
      'Incorrect email or password.',
    FirebaseAuthException(code: 'user-not-found') =>
      'No account found for that email.',
    FirebaseAuthException(code: 'email-already-in-use') =>
      'An account already exists for that email.',
    FirebaseAuthException(code: 'weak-password') =>
      'That password is too weak. Use 8+ characters with a letter and a '
          'number.',
    FirebaseAuthException(code: 'too-many-requests') =>
      'Too many attempts. Wait a few minutes, or reset your password.',
    FirebaseAuthException(code: 'invalid-email') =>
      'That email address looks invalid.',
    FirebaseAuthException(code: 'requires-recent-login') =>
      'Please sign out and sign in again, then retry.',
    _ when isSignInCancelled(e) => 'Sign-in was cancelled.',
    GoogleSignInException() =>
      "Couldn't sign in with Google. Try again.",
    FirebaseAuthException(:final message?) => message,
    FirebaseException(code: 'permission-denied' || 'unauthorized') =>
      "You don't have permission to do that.",
    FirebaseException(code: 'unavailable') =>
      'Network unavailable. Check your connection.',
    FirebaseException(:final message?) => message,
    null => 'Something went wrong.',
    _ => e.toString().replaceFirst('Exception: ', ''),
  };
}

/// Shows [error] in a snack bar; a cancelled sign-in shows nothing.
void showErrorSnackBar(BuildContext context, Object? error) {
  if (isSignInCancelled(error)) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(errorMessage(error))));
}

void showSnackBar(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
