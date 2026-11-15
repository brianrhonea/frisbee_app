import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/ui/error_message.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:google_sign_in/google_sign_in.dart';

void main() {
  group('isSignInCancelled', () {
    test('is true for closing or cancelling Google or Apple', () {
      expect(
        isSignInCancelled(
          const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
        ),
        isTrue,
      );
      for (final code in [
        'canceled',
        'popup-closed-by-user',
        'user-cancelled',
        'web-context-canceled',
      ]) {
        expect(
          isSignInCancelled(FirebaseAuthException(code: code)),
          isTrue,
          reason: code,
        );
      }
      // Through a Result, as commands hand it over.
      expect(
        isSignInCancelled(
          Result<void>.error(FirebaseAuthException(code: 'canceled')),
        ),
        isTrue,
      );
    });

    test('is false for real failures', () {
      expect(
        isSignInCancelled(FirebaseAuthException(code: 'invalid-credential')),
        isFalse,
      );
      expect(
        isSignInCancelled(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.clientConfigurationError,
          ),
        ),
        isFalse,
      );
      expect(isSignInCancelled(Exception('boom')), isFalse);
      expect(isSignInCancelled(null), isFalse);
    });
  });

  test('a Google failure reads as words, not the exception', () {
    expect(
      errorMessage(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
          description: 'x',
        ),
      ),
      "Couldn't sign in with Google. Try again.",
    );
  });

  testWidgets('a cancelled sign-in shows no snack bar', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    showErrorSnackBar(
      ctx,
      const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
    );
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);

    showErrorSnackBar(ctx, FirebaseAuthException(code: 'too-many-requests'));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
