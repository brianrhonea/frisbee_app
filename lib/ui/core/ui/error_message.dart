import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../utils/result.dart';

/// User-facing text for an error [Result] or exception.
String errorMessage(Object? error) {
  final e = error is Error ? error.error : error;
  return switch (e) {
    FirebaseAuthException(code: 'invalid-credential' || 'wrong-password') =>
      'Incorrect email or password.',
    FirebaseAuthException(code: 'user-not-found') =>
      'No account found for that email.',
    FirebaseAuthException(code: 'email-already-in-use') =>
      'An account already exists for that email.',
    FirebaseAuthException(code: 'weak-password') =>
      'Password must be at least 6 characters.',
    FirebaseAuthException(code: 'invalid-email') =>
      'That email address looks invalid.',
    FirebaseAuthException(code: 'requires-recent-login') =>
      'Please sign out and sign in again, then retry.',
    FirebaseAuthException(code: 'popup-closed-by-user' || 'canceled') =>
      'Sign-in was cancelled.',
    FirebaseAuthException(:final message?) => message,
    FirebaseException(code: 'permission-denied') =>
      "You don't have permission to do that.",
    FirebaseException(code: 'unavailable') =>
      'Network unavailable. Check your connection.',
    FirebaseException(:final message?) => message,
    null => 'Something went wrong.',
    _ => e.toString().replaceFirst('Exception: ', ''),
  };
}

void showErrorSnackBar(BuildContext context, Object? error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(errorMessage(error))));
}

void showSnackBar(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
