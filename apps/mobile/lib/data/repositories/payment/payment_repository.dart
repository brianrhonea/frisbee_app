import '../../../domain/models/payments.dart';
import '../../../utils/result.dart';

/// Online payments for tournament fees (Stripe Connect), through the API.
abstract class PaymentRepository {
  /// Stall 10's fee and Stripe's estimated card fee, for hosts setting a
  /// price.
  Future<Result<PaymentFees>> fees();

  /// The host team's payout account (owners only).
  Future<Result<PayoutAccount>> payouts(String teamId);

  /// A Stripe page where the owner connects or finishes the account.
  Future<Result<Uri>> payoutLink(String teamId);

  /// Whether the caller can pay online: [teamId]'s bid or spot fee, or
  /// without one their own entry fee.
  Future<Result<PayOptions>> payOptions(String tournamentId, {String? teamId});

  /// A Stripe Checkout page for that fee.
  Future<Result<Uri>> checkout(String tournamentId, {String? teamId});
}
