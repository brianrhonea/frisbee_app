import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';

/// Whether the app can reach Stall 10. The device's network status is a
/// hint (no network at all means offline straight away); a failed send
/// also marks it offline. While offline it asks the server
/// ([probe], the API's `GET /health`) every [probeEvery] until it
/// answers.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService({
    Stream<bool>? networkChanges,
    Future<bool>? initialNetwork,
    Future<bool> Function()? probe,
    this.probeEvery = const Duration(seconds: 15),
  }) : _probe = probe {
    _networkSub = networkChanges?.listen(_onNetwork);
    initialNetwork?.then(_onNetwork, onError: (_) {});
  }

  /// The device's network (connectivity_plus) and the API's health check.
  factory ConnectivityService.device(ApiClient? api) {
    final client = http.Client();
    bool any(List<ConnectivityResult> r) =>
        r.any((c) => c != ConnectivityResult.none);
    final device = Connectivity();
    return ConnectivityService(
      networkChanges: device.onConnectivityChanged.map(any),
      initialNetwork: device.checkConnectivity().then(any),
      probe: api == null
          ? null
          : () async {
              try {
                final r = await client
                    .get(api.baseUrl.resolve('/health'))
                    .timeout(const Duration(seconds: 5));
                return r.statusCode == 200;
              } on Exception {
                return false;
              }
            },
    );
  }

  final Future<bool> Function()? _probe;
  final Duration probeEvery;
  StreamSubscription<bool>? _networkSub;
  Timer? _probing;
  bool _online = true;
  bool _hasNetwork = true;
  bool _disposed = false;

  bool get online => _online;

  void _set(bool online) {
    if (_online == online || _disposed) return;
    _online = online;
    if (online) {
      _probing?.cancel();
      _probing = null;
    } else {
      _startProbing();
    }
    notifyListeners();
  }

  void _onNetwork(bool hasNetwork) {
    _hasNetwork = hasNetwork;
    if (!hasNetwork) {
      _set(false);
    } else {
      // A network is back; whether the server answers decides.
      unawaited(check());
    }
  }

  void _startProbing() {
    _probing?.cancel();
    _probing = Timer.periodic(probeEvery, (_) => unawaited(check()));
  }

  /// Asks the server now; true when it answered.
  Future<bool> check() async {
    if (!_hasNetwork) return false;
    final ok = await (_probe?.call() ?? Future.value(true));
    _set(ok);
    return ok;
  }

  /// A send failed for want of a connection.
  void reportOffline() => _set(false);

  /// Something reached the server.
  void reportOnline() {
    if (_hasNetwork) _set(true);
  }

  @override
  void dispose() {
    _disposed = true;
    _probing?.cancel();
    unawaited(_networkSub?.cancel());
    super.dispose();
  }
}
