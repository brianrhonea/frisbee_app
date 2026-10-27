import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../utils/command.dart';
import '../../../utils/platform_support.dart';
import '../../../utils/result.dart';

typedef Credentials = ({String email, String password});

class SignInViewModel extends ChangeNotifier {
  SignInViewModel({required AuthRepository authRepository})
    : _auth = authRepository {
    signIn = Command1<void, Credentials>(
      (c) => _auth.signInWithEmail(c.email, c.password),
    );
    signInWithGoogle = Command0<void>(_auth.signInWithGoogle);
    signInWithApple = Command0<void>(_auth.signInWithApple);
    sendPasswordReset = Command1<void, String>(_auth.sendPasswordReset);
  }

  final AuthRepository _auth;

  late final Command1<void, Credentials> signIn;
  late final Command0<void> signInWithGoogle;
  late final Command0<void> signInWithApple;
  late final Command1<void, String> sendPasswordReset;

  bool get showGoogle => PlatformSupport.googleSignIn;
  bool get showApple => PlatformSupport.appleSignIn;

  bool get busy =>
      signIn.running || signInWithGoogle.running || signInWithApple.running;

  /// The most recent failure across sign-in commands, if any.
  Result<void>? get lastError => [
    signIn,
    signInWithGoogle,
    signInWithApple,
  ].where((c) => c.error).map((c) => c.result).firstOrNull;
}
