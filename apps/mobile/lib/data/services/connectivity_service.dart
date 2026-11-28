import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';

/// Why Stall 10 can or can't be reached.
enum ConnectionStatus {
  /// Reachable, or not known to be otherwise.
  online,

  /// The device has no network.
  noNetwork,

  /// The device has a network but the server stayed unreachable after a
  /// confirming re-check.
  serverUnreachable,
}

/// Whether the app can reach Stall 10.
///
/// Offline means the device has no network, or the server stayed
/// unreachable after a confirming re-check. One failed request never flips
/// the state by itself: [reportFailure] only schedules a check (the API's
/// `GET /health` through the probe), which asks again before it gives up.
/// After the app starts and after it resumes there is a grace period
/// ([grace]) in which a failed check waits for the period to end and asks
/// once more, since sockets and radios are still waking up. While offline
/// it keeps asking, with a growing wait (from [probeEvery], up to four
/// times that) until the server answers.
class ConnectivityService extends ChangeNotifier with WidgetsBindingObserver {
  ConnectivityService({
    Stream<bool>? networkChanges,
    Future<bool>? initialNetwork,
    Future<bool> Function()? networkNow,
    Future<bool> Function()? probe,
    this.probeEvery = const Duration(seconds: 15),
    this.grace = const Duration(seconds: 8),
    this.onResumed,
    bool observeLifecycle = false,
  }) : _probe = probe,
       _networkNow = networkNow {
    _networkSub = networkChanges?.listen(_onNetwork);
    initialNetwork?.then(_onNetwork, onError: (_) {});
    _startGrace();
    if (observeLifecycle) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
  }

  /// The device's network (connectivity_plus) and the API's health check.
  /// [onResumed] runs when the app returns from the background (the API
  /// client drops its old connections there).
  factory ConnectivityService.device(
    ApiClient? api, {
    VoidCallback? onResumed,
  }) {
    bool any(List<ConnectivityResult> r) =>
        r.any((c) => c != ConnectivityResult.none);
    final device = Connectivity();
    return ConnectivityService(
      networkChanges: device.onConnectivityChanged.map(any),
      initialNetwork: device.checkConnectivity().then(any),
      networkNow: () => device.checkConnectivity().then(any),
      onResumed: onResumed,
      observeLifecycle: true,
      probe: api == null
          ? null
          : () async {
              // A fresh connection each time: after a resume the old ones
              // may be dead.
              final client = http.Client();
              try {
                final r = await client
                    .get(api.baseUrl.resolve('/health'))
                    .timeout(const Duration(seconds: 10));
                return r.statusCode == 200;
              } on Exception {
                return false;
              } finally {
                client.close();
              }
            },
    );
  }

  final Future<bool> Function()? _probe;
  final Future<bool> Function()? _networkNow;
  final Duration probeEvery;

  /// How long after the app starts or resumes a failed check waits before
  /// it can mark the server unreachable.
  final Duration grace;
  final VoidCallback? onResumed;

  StreamSubscription<bool>? _networkSub;
  Timer? _probing;
  Timer? _graceTimer;
  Completer<void>? _graceDone;
  Future<bool>? _confirming;
  int _backoff = 0;
  int _recoveries = 0;
  ConnectionStatus _status = ConnectionStatus.online;
  bool _hasNetwork = true;
  bool _disposed = false;
  bool _observing = false;

  ConnectionStatus get status => _status;
  bool get online => _status == ConnectionStatus.online;

  /// Whether the device has a network (the server may still be down).
  bool get hasNetwork => _hasNetwork;

  /// Counts the checks that found the server fine after a failure; the
  /// outbox tries what's waiting again when it changes.
  int get recoveries => _recoveries;

  void _startGrace() {
    _graceTimer?.cancel();
    if (grace <= Duration.zero) return;
    final done = _graceDone ??= Completer<void>();
    _graceTimer = Timer(grace, () {
      _graceDone = null;
      if (!done.isCompleted) done.complete();
    });
  }

  void _set(ConnectionStatus status) {
    if (_status == status || _disposed) return;
    final wasOnline = online;
    _status = status;
    if (online) {
      _probing?.cancel();
      _probing = null;
      _backoff = 0;
    } else if (wasOnline) {
      _scheduleProbe();
    }
    notifyListeners();
  }

  void _recovered() {
    if (_disposed) return;
    _recoveries++;
    if (online) {
      notifyListeners();
    } else {
      _set(ConnectionStatus.online);
    }
  }

  void _onNetwork(bool hasNetwork) {
    _hasNetwork = hasNetwork;
    if (!hasNetwork) {
      _set(ConnectionStatus.noNetwork);
    } else if (!online) {
      // A network is back; whether the server answers decides.
      unawaited(check());
    }
  }

  void _scheduleProbe() {
    _probing?.cancel();
    final factor = 1 << (_backoff > 2 ? 2 : _backoff);
    _probing = Timer(probeEvery * factor, () async {
      if (_disposed || online) return;
      await check();
      if (!_disposed && !online) {
        _backoff++;
        _scheduleProbe();
      }
    });
  }

  Future<bool> _ask() async {
    try {
      return await (_probe?.call() ?? Future.value(true));
    } on Object {
      return false;
    }
  }

  /// Asks twice, the second time after any grace period, before marking
  /// the server unreachable.
  Future<bool> _confirm() =>
      _confirming ??= _doConfirm().whenComplete(() => _confirming = null);

  Future<bool> _doConfirm() async {
    if (!_hasNetwork) return false;
    if (await _ask()) {
      _recovered();
      return true;
    }
    if (_disposed) return false;
    final waiting = _graceDone;
    if (waiting != null) await waiting.future;
    if (_disposed || !_hasNetwork) return false;
    if (await _ask()) {
      _recovered();
      return true;
    }
    if (!_disposed && _hasNetwork) _set(ConnectionStatus.serverUnreachable);
    return false;
  }

  /// Asks the server now; true when it answered. When online, a failed
  /// answer is confirmed before it counts; when offline, one answer
  /// brings it back.
  Future<bool> check() async {
    if (!_hasNetwork) return false;
    if (online) return _confirm();
    if (await _ask()) {
      _recovered();
      return true;
    }
    if (_status == ConnectionStatus.noNetwork && _hasNetwork) {
      _set(ConnectionStatus.serverUnreachable);
    }
    return false;
  }

  /// A request failed for want of a connection. Schedules a check rather
  /// than marking the app offline.
  void reportFailure() {
    if (_disposed) return;
    if (!_hasNetwork) {
      _set(ConnectionStatus.noNetwork);
    } else if (online) {
      unawaited(_confirm());
    }
  }

  /// Something reached the server.
  void reportOnline() {
    if (_hasNetwork) _set(ConnectionStatus.online);
  }

  /// The app returned from the background: start a grace period, read the
  /// network again and, when offline, ask the server now.
  Future<void> resumed() async {
    if (_disposed) return;
    _startGrace();
    onResumed?.call();
    final now = _networkNow;
    if (now != null) {
      try {
        final has = await now();
        if (_disposed) return;
        _onNetwork(has);
        return;
      } on Object {
        // Keep what's known.
      }
    }
    if (!online) unawaited(check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(resumed());
  }

  @override
  void dispose() {
    _disposed = true;
    _probing?.cancel();
    _graceTimer?.cancel();
    final done = _graceDone;
    _graceDone = null;
    if (done != null && !done.isCompleted) done.complete();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    unawaited(_networkSub?.cancel());
    super.dispose();
  }
}
