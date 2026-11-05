import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../domain/models/username.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import 'username_checker.dart';

typedef SignUpForm = ({
  String firstName,
  String lastName,
  String username,
  String email,
  String password,
});

class SignUpViewModel extends ChangeNotifier {
  SignUpViewModel({required AuthRepository authRepository})
    : _auth = authRepository,
      username = UsernameChecker(authRepository: authRepository) {
    signUp = Command1<void, SignUpForm>(_signUp);
  }

  final AuthRepository _auth;

  /// Checks the username field as it's typed.
  final UsernameChecker username;

  late final Command1<void, SignUpForm> signUp;

  Future<Result<void>> _signUp(SignUpForm f) async {
    final result = await _auth.signUpWithEmail(
      email: f.email,
      password: f.password,
      firstName: f.firstName,
      lastName: f.lastName,
      username: f.username,
    );
    if (result case Error(error: UsernameTakenException())) {
      username.markTaken();
    }
    return result;
  }

  @override
  void dispose() {
    username.dispose();
    signUp.dispose();
    super.dispose();
  }
}
