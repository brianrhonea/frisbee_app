import 'package:logging/logging.dart';

import '../../../domain/models/personal_details.dart';
import '../../../utils/result.dart';
import '../../services/api_client.dart';
import '../account_gate/account_gate.dart';
import '../auth/auth_repository.dart';
import 'personal_repository.dart';

final _log = Logger('PersonalDetailsRepository');

/// [PersonalDetailsRepository] through the API. Builds without
/// `API_BASE_URL` have no [api]: the status stays unknown and saving fails.
class PersonalDetailsRepositoryApi extends PersonalDetailsRepository {
  PersonalDetailsRepositoryApi({
    required ApiClient? api,
    required AuthRepository auth,
    AccountGate? gate,
  }) : _api = api,
       _auth = auth,
       _gate = gate {
    _auth.addListener(_onAuth);
    _onAuth();
  }

  final ApiClient? _api;
  final AuthRepository _auth;
  final AccountGate? _gate;
  String? _uid;
  PersonalDetailsStatus? _status;
  DateTime? _signUpBirthDate;
  bool _failed = false;

  /// Bumped per request and per account change, so only the latest answer
  /// for the current account is kept.
  int _generation = 0;

  @override
  PersonalDetailsStatus? get status => _status;

  @override
  bool get checkFailed => _failed;

  void _onAuth() {
    final uid = _auth.currentUser?.uid;
    if (uid == _uid) return;
    _uid = uid;
    _generation++;
    _status = null;
    _failed = false;
    notifyListeners();
    if (uid != null) refreshStatus();
  }

  @override
  Future<void> refreshStatus() async {
    final api = _api;
    final uid = _uid;
    if (api == null || uid == null) return;
    final generation = ++_generation;
    try {
      final s = PersonalDetailsStatus.fromMap(
        await api.send('GET', '/v1/me/personal/status'),
      );
      if (_uid != uid || _generation != generation) return;
      _status = s;
      _failed = false;
    } on Exception catch (e) {
      _log.warning('Personal details status unavailable', e);
      if (_uid != uid || _generation != generation) return;
      _status = null;
      _failed = true;
    }
    notifyListeners();
  }

  @override
  Future<Result<PersonalDetailsLoad>> load() => guard(() async {
    final api = _api;
    if (api == null) throw const ApiException('unavailable', _noApi);
    final json = await api.send('GET', '/v1/me/personal');
    final details = json['details'];
    return (
      details: details is Map
          ? PersonalDetails.fromMap(details.cast<String, Object?>())
          : null,
      email: json['email'] as String?,
      signUpBirthDate: switch (json['signUpBirthDate']) {
        final String s => parseIsoDate(s),
        _ => null,
      },
    );
  });

  @override
  Future<Result<void>> saveSignUpBirthDate(DateTime birthDate) =>
      guard(() async {
        final api = _api;
        if (api == null) throw const ApiException('unavailable', _noApi);
        try {
          await api.put('/v1/me/personal/birth-date', {
            'birthDate': isoDate(birthDate),
          });
        } on ApiException catch (e) {
          throw _refusal(e) ?? e;
        }
        // The status is unchanged: the details aren't complete yet. The
        // server set ageOk (the ApiClient refreshed the token).
        _gate?.clear(AccountGate.age);
      });

  @override
  Future<Result<void>> save(PersonalDetails details) => guard(() async {
    final api = _api;
    if (api == null) throw const ApiException('unavailable', _noApi);
    try {
      await api.put('/v1/me/personal', details.toMap());
    } on ApiException catch (e) {
      throw _refusal(e) ?? e;
    }
    _gate?.clear(AccountGate.age);
    _status = PersonalDetailsStatus(
      complete: true,
      required: _status?.required ?? false,
    );
    notifyListeners();
  });

  /// A 412 on the birth date as the exception the screens show; an
  /// adults-only refusal also sends the app to the dead-end screen.
  Exception? _refusal(ApiException e) {
    final x = birthDateRefusal(e.code, e.fields, e.message);
    if (x is TooYoungException) _gate?.markUnderAge();
    return x;
  }

  static const _noApi =
      "Personal details can't be saved in this version of the app. Update "
      'the app, or use stall10.app.';

  @override
  DateTime? takeSignUpBirthDate() {
    final d = _signUpBirthDate;
    _signUpBirthDate = null;
    return d;
  }

  @override
  set signUpBirthDate(DateTime? value) => _signUpBirthDate = value;

  ({String first, String last})? _signUpName;

  @override
  ({String first, String last})? takeSignUpName() {
    final n = _signUpName;
    _signUpName = null;
    return n;
  }

  @override
  set signUpName(({String first, String last})? value) => _signUpName = value;

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    super.dispose();
  }
}
