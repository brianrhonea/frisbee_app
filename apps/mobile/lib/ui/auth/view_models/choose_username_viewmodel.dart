import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/personal/personal_repository.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/person_name.dart';
import '../../../domain/models/username.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import 'username_checker.dart';

typedef NameAndUsername = ({
  String firstName,
  String lastName,
  String username,
});

/// "Your name and username", for people who signed up with Google or
/// Apple (or before usernames), and new accounts without a name. Google
/// and Apple accounts, and accounts without a name, give their first and
/// last name too (started from Google's or Apple's): it's the name on
/// their profile, posts and rosters. The router lets them in once both
/// are saved. The website's UsernameStep does the same.
class ChooseUsernameViewModel extends ChangeNotifier {
  ChooseUsernameViewModel({
    required AuthRepository authRepository,
    PersonalDetailsRepository? personalRepository,
  }) : _auth = authRepository,
       _personal = personalRepository,
       username = UsernameChecker(authRepository: authRepository) {
    needsUsername = _auth.needsUsername;
    asksName =
        !needsUsername ||
        PersonName.asks(
          _displayName,
          hasPassword: _auth.reauthMethod == SignInMethod.password,
        );
    save = Command1<void, NameAndUsername>(_save);
    signOut = Command0<void>(_auth.signOut);
  }

  final AuthRepository _auth;
  final PersonalDetailsRepository? _personal;
  final UsernameChecker username;

  /// They have no username yet. False when only the name is missing.
  late final bool needsUsername;

  /// The step asks their first and last name: Google and Apple accounts,
  /// and accounts without a usable name.
  late final bool asksName;

  late final Command1<void, NameAndUsername> save;
  late final Command0<void> signOut;

  String? get _displayName => _auth.currentUser?.displayName;

  /// The name boxes' start: Google's or Apple's name, split.
  ({String first, String last}) get prefillName =>
      PersonName.split(_displayName);

  /// The username suggested for [first] and [last] (or the account's name
  /// when the step doesn't ask it), until they edit it.
  String suggestionFor(String first, String last) =>
      Username.suggest(asksName ? PersonName.join(first, last) : _displayName);

  String get title => asksName && needsUsername
      ? 'Your name and username'
      : asksName
      ? 'Your name'
      : 'Pick your username';

  String get subtitle => asksName && needsUsername
      ? 'Your name shows on your profile, posts and team rosters. Your '
            'username is how teammates find and mention you, as @name.'
      : asksName
      ? 'It shows on your profile, posts and team rosters.'
      : "It's how teammates find and mention you. We started one from "
            'your name; change it to anything you like.';

  Future<Result<void>> _save(NameAndUsername f) async {
    if (asksName) {
      final first = f.firstName.trim();
      final last = f.lastName.trim();
      if (first.isEmpty) {
        return Result.error(Exception('Enter your first name'));
      }
      if (last.isEmpty) {
        return Result.error(Exception('Enter your last name'));
      }
      // "About you" starts the legal name from these boxes.
      _personal?.signUpName = (first: first, last: last);
      if (PersonName.join(first, last) != (_displayName ?? '').trim()) {
        final named = await _auth.saveName(firstName: first, lastName: last);
        if (named is Error) return named;
      }
    }
    if (!needsUsername) return const Result.ok(null);
    final result = await _auth.claimUsername(f.username);
    if (result case Error(error: UsernameTakenException())) {
      username.markTaken();
    }
    return result;
  }

  @override
  void dispose() {
    username.dispose();
    save.dispose();
    signOut.dispose();
    super.dispose();
  }
}
