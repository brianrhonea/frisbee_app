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

  /// Under 18, no account is made (launch is adults only; the server
  /// checks again and its own message is shown if it refuses).
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
    _personal.signUpName = (first: f.firstName.trim(), last: f.lastName.trim());
    final result = await _auth.signUpWithEmail(
      email: f.email,
      password: f.password,
      firstName: f.firstName,
      lastName: f.lastName,
      username: f.username,
      // The birth date goes first, right after the login exists: the
      // server refuses the username and the directory profile until it
      // is saved (the `ageOk` claim).
      afterCreate: () => _saveBirthDate(f.birthDate),
    );
    if (result case Error(error: UsernameTakenException())) {
      username.markTaken();
    }
    return result;
  }

  /// Kept (encrypted) so "About you" has it after a restart or on another
  /// device. Never holds up sign-up when it can't be reached (offline, no
  /// API): the in-memory copy still fills the form, whose save checks
  /// again, and the username waits for it. Returns false when the server
  /// refused the date as under 18: the app then shows the adults-only
  /// screen, and nothing else is written.
  Future<bool> _saveBirthDate(DateTime birthDate) async {
    final saved = await _personal.saveSignUpBirthDate(birthDate);
    return saved is! Error || saved.error is! TooYoungException;
  }

  @override
  void dispose() {
    username.dispose();
    signUp.dispose();
    super.dispose();
  }
}
