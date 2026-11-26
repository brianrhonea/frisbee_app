import 'package:flutter/foundation.dart';

import '../../../data/repositories/account_gate/account_gate.dart';
import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/personal/personal_repository.dart';
import '../../../domain/models/person_name.dart';
import '../../../domain/models/personal_details.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// The personal details form: the step of signing up that asks for the
/// birth date ([finishing]), or Settings → Personal details.
class PersonalDetailsViewModel extends ChangeNotifier {
  PersonalDetailsViewModel({
    required PersonalDetailsRepository personalRepository,
    required AuthRepository authRepository,
    this.finishing = false,
    AccountGate? accountGate,
  }) : _personal = personalRepository,
       _auth = authRepository,
       _gate = accountGate {
    load = Command0<void>(_load)..execute();
    save = Command1<void, PersonalDetails>(_save);
    signOut = Command0<void>(_auth.signOut);
  }

  final PersonalDetailsRepository _personal;
  final AuthRepository _auth;
  final AccountGate? _gate;

  /// Signing up: a birth date under 18 leads to the adults-only screen.
  final bool finishing;

  late final Command0<void> load;
  late final Command1<void, PersonalDetails> save;
  late final Command0<void> signOut;

  PersonalDetails? _details;
  String? _email;
  DateTime? _prefillBirthDate;
  ({String first, String last})? _prefillTypedName;
  bool _birthDateSaved = false;

  PersonalDetails? get details => _details;
  String? get email => _email ?? _auth.currentUser?.email;

  /// The sign-up form's birthday, when there are no details yet: the copy
  /// saved at sign-up, else the one still in memory.
  DateTime? get prefillBirthDate => _prefillBirthDate;

  /// The birth date is saved on the server, so it can't be changed (the
  /// API refuses a different one): the form shows it read-only. A date only
  /// typed into the sign-up form (not saved yet) can still be edited.
  bool get birthDateLocked => _birthDateSaved;

  /// Where the legal name starts: the first and last name just typed
  /// (sign-up, or "Your name and username"), else their profile name
  /// split. The legal name stays separate and private.
  ({String first, String last}) get prefillName =>
      _prefillTypedName ?? PersonName.split(_auth.currentUser?.displayName);

  Future<Result<void>> _load() async {
    _prefillBirthDate = _personal.takeSignUpBirthDate();
    _prefillTypedName = _personal.takeSignUpName();
    final result = await _personal.load();
    if (result case Ok(:final value)) {
      _details = value.details;
      _email = value.email;
      _prefillBirthDate = value.signUpBirthDate ?? _prefillBirthDate;
      _birthDateSaved = value.details != null || value.signUpBirthDate != null;
      notifyListeners();
      return const Result.ok(null);
    }
    if (finishing) {
      // Finishing sign-up never waits on this (offline, or no API): the
      // form starts from what's in memory.
      notifyListeners();
      return const Result.ok(null);
    }
    return result as Error<void>;
  }

  /// A birthday under 18 on the sign-up step (Google and Apple ask none
  /// first): nothing is sent; the app shows the adults-only screen, where
  /// they can sign out or delete the account.
  void refuseUnderAge() {
    if (!finishing) return;
    _gate?.markUnderAge();
  }

  Future<Result<void>> _save(PersonalDetails d) async {
    final result = await _personal.save(d);
    // The API's own check (e.g. the device's date is off).
    if (result case Error(error: TooYoungException())) {
      _gate?.markUnderAge();
    }
    if (result is Ok) {
      _details = d;
      _birthDateSaved = true;
      notifyListeners();
    }
    return result;
  }

  @override
  void dispose() {
    load.dispose();
    save.dispose();
    signOut.dispose();
    super.dispose();
  }
}
