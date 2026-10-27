import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../utils/command.dart';

typedef SignUpForm = ({String name, String email, String password});

class SignUpViewModel extends ChangeNotifier {
  SignUpViewModel({required AuthRepository authRepository})
    : _auth = authRepository {
    signUp = Command1<void, SignUpForm>(
      (f) => _auth.signUpWithEmail(
        email: f.email,
        password: f.password,
        displayName: f.name,
      ),
    );
  }

  final AuthRepository _auth;

  late final Command1<void, SignUpForm> signUp;
}
