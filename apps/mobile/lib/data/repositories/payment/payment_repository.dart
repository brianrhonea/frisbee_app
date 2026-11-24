import '../../../domain/models/payments.dart';
import '../../../utils/result.dart';

/// Online payments for tournament fees, through the API. Stall 10 takes
/// each payment and sends the host its fee once the event is over.
abstract class PaymentRepository {
  /// Whether the API is there: hosts' marks then go through it (and into
  /// the payment history) instead of straight to Firestore.
  bool get available;

  /// The payer says they'll pay another way ([offline]), or takes it back.
  Future<Result<void>> payOffline(
    String tournamentId, {
    String? teamId,
    required bool offline,
  });

  /// The host marks [payerId]'s fee (a team or a player) with a [note].
  Future<Result<void>> mark(
    String tournamentId,
    String payerId, {
    required bool paid,
    required String note,
  });

  /// Stall 10's fee and Stripe's estimated card fee, for hosts setting a
  /// price.
  Future<Result<PaymentFees>> fees();

  /// The host team's payout account (owners only).
  Future<Result<PayoutAccount>> payouts(String teamId);

  /// A Stripe page where the owner connects or finishes the account.
  Future<Result<Uri>> payoutLink(String teamId);

  /// A session for Stripe's setup form inside the app (an AccountSession's
  /// client secret, handed to the website's /embed/payouts page in a
  /// WebView); owners only.
  Future<Result<String>> payoutSession(String teamId);

  /// Whether the caller can pay online: [teamId]'s bid or spot fee, or
  /// without one their own entry fee.
  Future<Result<PayOptions>> payOptions(String tournamentId, {String? teamId});

  /// A Stripe Checkout page for that fee.
  Future<Result<Uri>> checkout(String tournamentId, {String? teamId});

  /// The same fee in the app's own payment sheet (a PaymentIntent on
  /// Stall 10's account).
  Future<Result<PaymentSheetRequest>> paymentSheet(
    String tournamentId, {
    String? teamId,
  });

  /// The event's organizers refund [payerId]'s fee paid online (the fee
  /// itself, not the service and processing fees).
  Future<Result<void>> refund(String tournamentId, String payerId);

  /// The host's fees paid online: held, sent, refunded (its organizers).
  Future<Result<Earnings>> earnings(String teamId);
}
