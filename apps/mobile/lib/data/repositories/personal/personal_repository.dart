import 'package:flutter/foundation.dart';

import '../../../domain/models/personal_details.dart';
import '../../../utils/result.dart';

/// The signed-in player's personal details (`/v1/me/personal`), which
/// only they see. Notifies when [status] changes, so the router can ask a
/// new account for them before anything else.
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

  /// Their details (null if not given yet) and the account's email.
  Future<Result<({PersonalDetails? details, String? email})>> load();

  /// Saves [details]; fails with [TooYoungException] under 13.
  Future<Result<void>> save(PersonalDetails details);

  /// The birthday from the sign-up form, in memory only, so the details
  /// step doesn't ask it again. Read once.
  DateTime? takeSignUpBirthDate();
  set signUpBirthDate(DateTime? value);
}
