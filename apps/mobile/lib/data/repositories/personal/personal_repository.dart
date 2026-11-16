import 'package:flutter/foundation.dart';

import '../../../domain/models/personal_details.dart';
import '../../../utils/result.dart';

/// The signed-in player's personal details (`/v1/me/personal`), which
/// only they see. Notifies when [status] changes, so the router can ask a
/// new account for them before anything else.
/// What [PersonalDetailsRepository.load] reads.
typedef PersonalDetailsLoad = ({
  PersonalDetails? details,
  String? email,
  DateTime? signUpBirthDate,
});

abstract class PersonalDetailsRepository extends ChangeNotifier {
  /// Null while unknown, or when it can't be read (no API in this build,
  /// offline): then nobody is held up.
  PersonalDetailsStatus? get status;

  /// A new account that hasn't given them: the app asks first.
  bool get mustComplete {
    final s = status;
    return s != null && s.required && !s.complete;
  }

  /// An older account without them: a card suggests adding them.
  bool get shouldPrompt {
    final s = status;
    return s != null && !s.required && !s.complete;
  }

  Future<void> refreshStatus();

  /// Their details (null if not given yet), the account's email and,
  /// before the details are given, the birthday saved at sign-up.
  Future<Result<PersonalDetailsLoad>> load();

  /// Saves [details]; fails with [TooYoungException] under 13.
  Future<Result<void>> save(PersonalDetails details);

  /// Saves the email sign-up form's birthday, encrypted like the details
  /// (`PUT /v1/me/personal/birth-date`), so "About you" has it after a
  /// restart or on another device. Doesn't complete the details; refused
  /// once they're saved. Fails with [TooYoungException] under 13.
  Future<Result<void>> saveSignUpBirthDate(DateTime birthDate);

  /// The birthday from the sign-up form, in memory only, so the details
  /// step doesn't ask it again. Read once.
  DateTime? takeSignUpBirthDate();
  set signUpBirthDate(DateTime? value);

  /// The first and last name just typed (sign-up, or "Your name and
  /// username"), in memory only, to start the legal name from. Read once.
  ({String first, String last})? takeSignUpName();
  set signUpName(({String first, String last})? value);
}
