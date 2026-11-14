import 'package:logging/logging.dart';

import '../../../domain/models/personal_details.dart';
import '../../../utils/result.dart';
import '../../services/api_client.dart';
import '../auth/auth_repository.dart';
import 'personal_repository.dart';

final _log = Logger('PersonalDetailsRepository');

/// [PersonalDetailsRepository] through the API. Builds without
/// `API_BASE_URL` have no [api]: the status stays unknown and saving fails.
class PersonalDetailsRepositoryApi extends PersonalDetailsRepository {
  PersonalDetailsRepositoryApi({
    required ApiClient? api,
    required AuthRepository auth,
  }) : _api = api,
       _auth = auth {
    _auth.addListener(_onAuth);
    _onAuth();
  }

  final ApiClient? _api;
  final AuthRepository _auth;
  String? _uid;
  PersonalDetailsStatus? _status;
  DateTime? _signUpBirthDate;

  @override
  PersonalDetailsStatus? get status => _status;

  void _onAuth() {
    final uid = _auth.currentUser?.uid;
    if (uid == _uid) return;
    _uid = uid;
    _status = null;
    notifyListeners();
    if (uid != null) refreshStatus();
  }

  @override
  Future<void> refreshStatus() async {
    final api = _api;
    final uid = _uid;
    if (api == null || uid == null) return;
    try {
      final s = PersonalDetailsStatus.fromMap(
        await api.send('GET', '/v1/me/personal/status'),
      );
      if (_uid != uid) return;
      _status = s;
    } on Exception catch (e) {
      // Unknown: let them in rather than lock them out.
      _log.info('Personal details status unavailable', e);
      if (_uid != uid) return;
      _status = null;
    }
    notifyListeners();
  }

  @override
  Future<Result<({PersonalDetails? details, String? email})>> load() =>
      guard(() async {
        final api = _api;
        if (api == null) throw const ApiException('unavailable', _noApi);
        final json = await api.send('GET', '/v1/me/personal');
        final details = json['details'];
        return (
          details: details is Map
              ? PersonalDetails.fromMap(details.cast<String, Object?>())
              : null,
          email: json['email'] as String?,
        );
      });

  @override
  Future<Result<void>> save(PersonalDetails details) => guard(() async {
    final api = _api;
    if (api == null) throw const ApiException('unavailable', _noApi);
    try {
      await api.put('/v1/me/personal', details.toMap());
    } on ApiException catch (e) {
      if (e.code == 'failed_precondition' &&
          e.fields.containsKey('birthDate')) {
        throw const TooYoungException();
      }
      rethrow;
    }
    _status = PersonalDetailsStatus(
      complete: true,
      required: _status?.required ?? false,
    );
    notifyListeners();
  });

  static const _noApi = "Personal details can't be saved in this build.";

  @override
  DateTime? takeSignUpBirthDate() {
    final d = _signUpBirthDate;
    _signUpBirthDate = null;
    return d;
  }

  @override
  set signUpBirthDate(DateTime? value) => _signUpBirthDate = value;

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    super.dispose();
  }
}
