import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../../../domain/models/agreement.dart';
import '../../../utils/result.dart';
import '../../services/api_client.dart';
import '../account_gate/account_gate.dart';
import '../auth/auth_repository.dart';

final _log = Logger('AgreementRepository');

/// Whether the signed-in member has agreed to the current Community
/// Guidelines and Terms (`/v1/me/agreement`). Notifies when that changes,
/// so the router can ask before anything else.
abstract class AgreementRepository extends ChangeNotifier {
  /// Null until the first answer arrives, or in a build with no API: then
  /// nobody is held up. An error or an unreadable answer is not "unknown":
  /// see [checkFailed].
  bool? get agreed;

  /// The last check for the signed-in account failed (offline, an API
  /// error, or an answer that isn't a plain true or false). The router holds
  /// the app on a "Couldn't check your account" screen until [refresh]
  /// succeeds, so a bad answer never lets someone past the terms.
  bool get checkFailed => false;

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
  bool? _agreed;
  bool _failed = false;

  /// Bumped per request and per account change, so only the latest answer
  /// for the current account is kept.
  int _generation = 0;

  @override
  bool? get agreed => _agreed;

  @override
  bool get checkFailed => _failed;

  void _onAuth() {
    final uid = _auth.currentUser?.uid;
    if (uid == _uid) return;
    _uid = uid;
    _generation++;
    _agreed = null;
    _failed = false;
    notifyListeners();
    if (uid != null) refresh();
  }

  @override
  Future<void> refresh() async {
    final api = _api;
    final uid = _uid;
    if (api == null || uid == null) return;
    final generation = ++_generation;
    try {
      final json = await api.send('GET', '/v1/me/agreement');
      final agreed = json['agreed'];
      if (agreed is! bool) {
        throw const FormatException('The agreement answer is not true/false');
      }
      if (_uid != uid || _generation != generation) return;
      _agreed = agreed;
      _failed = false;
    } on Exception catch (e) {
      _log.warning('Agreement status unavailable', e);
      if (_uid != uid || _generation != generation) return;
      _agreed = null;
      _failed = true;
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
    _gate?.clear(AccountGate.terms);
    notifyListeners();
  });

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    super.dispose();
  }
}
