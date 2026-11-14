import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/personal/personal_repository.dart';
import '../../../domain/models/personal_details.dart';
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
  DateTime birthDate,
});

class SignUpViewModel extends ChangeNotifier {
  SignUpViewModel({
    required AuthRepository authRepository,
    required PersonalDetailsRepository personalRepository,
  }) : _auth = authRepository,
       _personal = personalRepository,
       username = UsernameChecker(authRepository: authRepository) {
    signUp = Command1<void, SignUpForm>(_signUp);
  }

  final AuthRepository _auth;
  final PersonalDetailsRepository _personal;

  /// Checks the username field as it's typed.
  final UsernameChecker username;

  late final Command1<void, SignUpForm> signUp;

  /// Under 13, no account is made (the details step checks again).
  String? birthDateProblemOn(DateTime? birth) {
    final n = DateTime.now();
    return birthDateProblem(birth, DateTime(n.year, n.month, n.day));
  }

  Future<Result<void>> _signUp(SignUpForm f) async {
    if (birthDateProblemOn(f.birthDate) case final problem?) {
      return Result.error(Exception(problem));
    }
    // Kept in memory for the details step, which comes next.
    _personal.signUpBirthDate = f.birthDate;
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
