import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/personal/personal_repository.dart';
import '../../../domain/models/personal_details.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// The personal details form: the last step of signing up ([finishing]),
/// or Settings → Personal details.
class PersonalDetailsViewModel extends ChangeNotifier {
  PersonalDetailsViewModel({
    required PersonalDetailsRepository personalRepository,
    required AuthRepository authRepository,
    this.finishing = false,
  }) : _personal = personalRepository,
       _auth = authRepository {
    load = Command0<void>(_load)..execute();
    save = Command1<void, PersonalDetails>(_save);
    signOut = Command0<void>(_auth.signOut);
  }

  final PersonalDetailsRepository _personal;
  final AuthRepository _auth;

  /// Signing up: under 13, the new account is removed.
  final bool finishing;

  late final Command0<void> load;
  late final Command1<void, PersonalDetails> save;
  late final Command0<void> signOut;

  PersonalDetails? _details;
  String? _email;
  DateTime? _prefillBirthDate;
  bool _tooYoung = false;

  PersonalDetails? get details => _details;
  String? get email => _email ?? _auth.currentUser?.email;

  /// The sign-up form's birthday, when there are no details yet.
  DateTime? get prefillBirthDate => _prefillBirthDate;

  /// Their profile name, split, to start the legal name from.
  ({String first, String last}) get prefillName {
    final parts = (_auth.currentUser?.displayName ?? '').trim().split(
      RegExp(r'\s+'),
    );
    return (
      first: parts.first,
      last: parts.length > 1 ? parts.sublist(1).join(' ') : '',
    );
  }

  /// Refused for being under 13; the account is being (or has been) removed.
  bool get tooYoung => _tooYoung;

  Future<Result<void>> _load() async {
    _prefillBirthDate = _personal.takeSignUpBirthDate();
    if (finishing) {
      // A new account has none yet; nothing to fetch (or decrypt).
      notifyListeners();
      return const Result.ok(null);
    }
    final result = await _personal.load();
    if (result case Ok(:final value)) {
      _details = value.details;
      _email = value.email;
      notifyListeners();
      return const Result.ok(null);
    }
    return result as Error<void>;
  }

  /// Finishing sign-up with a birthday under 13 (Google and Apple ask none
  /// first): nothing is sent, and the new account is removed.
  Future<void> refuseUnderAge() async {
    if (!finishing || _tooYoung) return;
    _tooYoung = true;
    notifyListeners();
    // Needs a recent sign-in, which a new account has; if it fails (they
    // came back days later), sign out: the gate keeps the account out of
    // the app either way.
    if (await _auth.deleteAccount() is Error) await _auth.signOut();
  }

  Future<Result<void>> _save(PersonalDetails d) async {
    final result = await _personal.save(d);
    // The API's own check (e.g. the device's date is off).
    if (result case Error(error: TooYoungException()) when finishing) {
      await refuseUnderAge();
    }
    if (result is Ok) _details = d;
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
