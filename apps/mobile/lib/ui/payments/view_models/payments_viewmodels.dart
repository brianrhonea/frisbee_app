import 'package:flutter/foundation.dart';

import '../../../data/repositories/payment/payment_repository.dart';
import '../../../domain/models/payments.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Opens a web page outside the app (Stripe's pages); false if it couldn't.
typedef OpenPage = Future<bool> Function(Uri url);

/// A host owner's payout account: connect Stripe, finish setting it up,
/// see that it's ready. Hidden while online payments aren't available.
class PayoutsViewModel extends ChangeNotifier {
  PayoutsViewModel({
    required PaymentRepository payments,
    required this.teamId,
    required OpenPage open,
  }) : _payments = payments,
       _open = open {
    load = Command0(_load)..execute();
    connect = Command0(_connect);
  }

  final PaymentRepository _payments;
  final OpenPage _open;
  final String teamId;

  late final Command0<void> load;
  late final Command0<void> connect;

  PayoutAccount _account = PayoutAccount.unavailable;
  PayoutAccount get account => _account;

  Future<Result<void>> _load() async {
    final r = await _payments.payouts(teamId);
    if (r case Ok(:final value)) {
      _account = value;
      notifyListeners();
    }
    return r;
  }

  /// Opens Stripe's onboarding. Coming back, [load] shows where it stands.
  Future<Result<void>> _connect() async {
    final r = await _payments.payoutLink(teamId);
    switch (r) {
      case Ok(:final value):
        if (!await _open(value)) {
          return Result.error(Exception("Couldn't open Stripe."));
        }
        return const Result.ok(null);
      case Error(:final error):
        return Result.error(error);
    }
  }
}

/// One fee the user can pay: a team's bid or spot fee ([teamId]), or their
/// own entry fee. Shows a Pay button only when the host takes payments
/// through Stall 10; otherwise the host's own instructions stand.
class PayOnlineViewModel extends ChangeNotifier {
  PayOnlineViewModel({
    required PaymentRepository payments,
    required this.tournamentId,
    this.teamId,
    required OpenPage open,
  }) : _payments = payments,
       _open = open {
    load = Command0(_load)..execute();
    pay = Command0(_pay);
  }

  final PaymentRepository _payments;
  final OpenPage _open;
  final String tournamentId;
  final String? teamId;

  late final Command0<void> load;
  late final Command0<void> pay;

  PayOptions? _options;
  PayOptions? get options => _options;

  /// Sent to Stripe and not yet back with an answer: on returning, the
  /// button gives way to "Checking your payment…" until [load] finishes,
  /// so nobody pays twice while Stripe confirms.
  bool _awaitingReturn = false;

  /// Showing "Checking your payment…".
  bool get checking => _awaitingReturn && load.running;

  /// Back from Stripe but the check failed (no connection): Pay stays
  /// hidden, with a way to check again, rather than offering stale options.
  bool get returnFailed => _awaitingReturn && !load.running && load.error;

  /// Whether to show the Pay button.
  bool get canPay => _options?.online == true && !checking && !returnFailed;

  Future<Result<void>> _load() async {
    if (_awaitingReturn) notifyListeners();
    final r = await _payments.payOptions(tournamentId, teamId: teamId);
    if (r case Ok(:final value)) {
      _options = value;
      // Paid or still clearing: done waiting. Otherwise they may still be
      // on Stripe's page (another tab, or cancelled): keep the button.
      _awaitingReturn = false;
    }
    notifyListeners();
    return r;
  }

  /// Opens Stripe Checkout. The payment shows as paid once Stripe confirms
  /// it (the payments list updates by itself).
  Future<Result<void>> _pay() async {
    final r = await _payments.checkout(tournamentId, teamId: teamId);
    switch (r) {
      case Ok(:final value):
        if (!await _open(value)) {
          return Result.error(Exception("Couldn't open the payment page."));
        }
        _awaitingReturn = true;
        return const Result.ok(null);
      case Error(:final error):
        return Result.error(error);
    }
  }
}

/// Stall 10's fee and Stripe's, so a host sees what reaches them of a fee
/// paid online. Unavailable (nothing shown) until the server says
/// payments are on.
class PaymentFeesViewModel extends ChangeNotifier {
  PaymentFeesViewModel({required PaymentRepository payments})
    : _payments = payments {
    load = Command0(_load)..execute();
  }

  final PaymentRepository _payments;

  late final Command0<void> load;

  PaymentFees _fees = PaymentFees.unavailable;
  PaymentFees get fees => _fees;

  Future<Result<void>> _load() async {
    final r = await _payments.fees();
    if (r case Ok(:final value)) {
      _fees = value;
      notifyListeners();
    }
    return r;
  }
}
