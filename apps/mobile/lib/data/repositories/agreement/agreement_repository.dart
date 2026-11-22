import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../../../domain/models/agreement.dart';
import '../../../utils/result.dart';
import '../../services/api_client.dart';
import '../auth/auth_repository.dart';

final _log = Logger('AgreementRepository');

/// Whether the signed-in member has agreed to the current Community
/// Guidelines and Terms (`/v1/me/agreement`). Notifies when that changes,
/// so the router can ask before anything else.
abstract class AgreementRepository extends ChangeNotifier {
  /// Null while unknown or unreadable (no API in this build, offline):
  /// then nobody is held up.
  bool? get agreed;

  /// A definite "not yet": the app asks first.
  bool get mustAgree => agreed == false;

  Future<void> refresh();

  /// Records agreeing to [termsVersion].
  Future<Result<void>> agree();
}

/// [AgreementRepository] through the API.
class AgreementRepositoryApi extends AgreementRepository {
  AgreementRepositoryApi({
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
  bool? _agreed;

  @override
  bool? get agreed => _agreed;

  void _onAuth() {
    final uid = _auth.currentUser?.uid;
    if (uid == _uid) return;
    _uid = uid;
    _agreed = null;
    notifyListeners();
    if (uid != null) refresh();
  }

  @override
  Future<void> refresh() async {
    final api = _api;
    final uid = _uid;
    if (api == null || uid == null) return;
    try {
      final json = await api.send('GET', '/v1/me/agreement');
      if (_uid != uid) return;
      _agreed = json['agreed'] == true;
    } on Exception catch (e) {
      // Unknown: let them in rather than lock them out.
      _log.info('Agreement status unavailable', e);
      if (_uid != uid) return;
      _agreed = null;
    }
    notifyListeners();
  }

  @override
  Future<Result<void>> agree() => guard(() async {
    final api = _api;
    if (api == null) {
      throw const ApiException(
        'unavailable',
        "This version of the app can't save that. Update the app.",
      );
    }
    await api.put('/v1/me/agreement', {'version': termsVersion});
    _agreed = true;
    notifyListeners();
  });

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    super.dispose();
  }
}
