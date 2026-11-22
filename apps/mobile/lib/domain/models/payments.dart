// Online payments for tournament and league fees (Stripe Connect). The
// server's answers, as in packages/shared/src/payments.ts.

/// Where a host's Stripe account stands.
enum PayoutStatus {
  /// Not connected.
  none,

  /// Connected, but Stripe still needs details before it can take payments.
  pending,

  /// Takes payments.
  ready;

  static PayoutStatus parse(Object? v) => switch (v) {
    'pending' => pending,
    'ready' => ready,
    _ => none,
  };
}

/// A host's payout account (`GET /v1/teams/:id/payouts`, owners only).
class PayoutAccount {
  const PayoutAccount({
    required this.available,
    required this.status,
    required this.feeLabel,
  });

  /// Not available: this server doesn't take payments yet; hide the section.
  static const unavailable = PayoutAccount(
    available: false,
    status: PayoutStatus.none,
    feeLabel: '',
  );

  final bool available;
  final PayoutStatus status;

  /// Stall 10's fee, e.g. "1% + $1".
  final String feeLabel;

  factory PayoutAccount.fromMap(Map<String, Object?> m) => PayoutAccount(
    available: m['available'] == true,
    status: PayoutStatus.parse(m['status']),
    feeLabel: m['feeLabel'] as String? ?? '',
  );
}

/// Whether the caller can pay a fee online (`GET /v1/tournaments/:id/pay`).
class PayOptions {
  const PayOptions({
    required this.online,
    required this.amountCents,
    int? chargeCents,
    this.processingCents = 0,
    required this.feeCents,
    required this.feeLabel,
    required this.paid,
    this.reason,
    this.processing = false,
  }) : chargeCents = chargeCents ?? amountCents;

  /// The host takes payments through Stall 10 and this fee can be paid online.
  final bool online;

  /// The fee the host set.
  final int amountCents;

  /// What paying online costs: [amountCents] plus [processingCents].
  final int chargeCents;

  /// The processing fee added when the host passes the fees on (else 0).
  final int processingCents;

  /// A bank payment is clearing (days): no Pay button until it settles.
  final bool processing;

  /// Stall 10's part of the amount (included, not added).
  final int feeCents;
  final String feeLabel;
  final bool paid;

  /// Why it can't be paid online, when it can't.
  final String? reason;

  factory PayOptions.fromMap(Map<String, Object?> m) => PayOptions(
    online: m['online'] == true,
    amountCents: (m['amountCents'] as num?)?.toInt() ?? 0,
    chargeCents: (m['chargeCents'] as num?)?.toInt(),
    processingCents: (m['processingCents'] as num?)?.toInt() ?? 0,
    feeCents: (m['feeCents'] as num?)?.toInt() ?? 0,
    feeLabel: m['feeLabel'] as String? ?? '',
    paid: m['paid'] == true,
    reason: m['reason'] as String?,
    processing: m['pending'] == 'processing',
  );
}

/// "$400", "$1.60" (centsLabel in packages/shared).
String centsLabel(int cents) {
  final whole = cents ~/ 100;
  final rest = cents % 100;
  return rest == 0 ? '\$$whole' : '\$$whole.${rest.toString().padLeft(2, '0')}';
}

/// A fee as a percentage (basis points: 100 = 1%) plus a fixed amount:
/// Stall 10's fee, or Stripe's card fee (PlatformFee in packages/shared).
class FeeRate {
  const FeeRate({required this.percentBps, required this.fixedCents});

  final int percentBps;
  final int fixedCents;

  /// The fee on [amountCents], rounded to the cent (platformFeeCents).
  int on(int amountCents) =>
      (amountCents * percentBps / 10000).round() + fixedCents;

  /// "1% + $1", "2.9% + $0.30" (platformFeeLabel).
  String get label {
    final pct = percentBps > 0
        ? '${(percentBps / 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')}%'
        : '';
    final fixed = fixedCents > 0 ? centsLabel(fixedCents) : '';
    final parts = [pct, fixed].where((s) => s.isNotEmpty);
    return parts.isEmpty ? 'nothing' : parts.join(' + ');
  }

  static FeeRate fromMap(Object? m, FeeRate fallback) => m is Map
      ? FeeRate(
          percentBps: (m['percentBps'] as num?)?.toInt() ?? fallback.percentBps,
          fixedCents: (m['fixedCents'] as num?)?.toInt() ?? fallback.fixedCents,
        )
      : fallback;
}

/// Where a fee paid online goes (feeBreakdown in packages/shared).
typedef FeeBreakdown = ({
  int amountCents,
  int platformCents,
  int stripeCents,
  int hostCents,
});

/// The fees on a payment made online (`GET /v1/payments/fees`), for hosts
/// setting a price.
class PaymentFees {
  const PaymentFees({
    required this.available,
    required this.platform,
    required this.card,
  });

  /// 1% + $1 (defaultPlatformFee).
  static const defaultPlatform = FeeRate(percentBps: 100, fixedCents: 100);

  /// Stripe's standard US online card rate, 2.9% + 30¢ (stripeCardFeeEstimate).
  static const defaultCard = FeeRate(percentBps: 290, fixedCents: 30);

  static const unavailable = PaymentFees(
    available: false,
    platform: defaultPlatform,
    card: defaultCard,
  );

  /// Not available: this server doesn't take payments; say nothing about them.
  final bool available;

  /// Stall 10's fee.
  final FeeRate platform;

  /// Stripe's card fee, an estimate.
  final FeeRate card;

  factory PaymentFees.fromMap(Map<String, Object?> m) => PaymentFees(
    available: m['available'] == true,
    platform: FeeRate.fromMap(m['platform'], defaultPlatform),
    card: FeeRate.fromMap(m['card'], defaultCard),
  );

  /// How [amountCents] splits between Stall 10, Stripe and the host.
  FeeBreakdown breakdown(int amountCents) {
    final platformCents = platform.on(amountCents);
    final stripeCents = card.on(amountCents);
    final host = amountCents - platformCents - stripeCents;
    return (
      amountCents: amountCents,
      platformCents: platformCents,
      stripeCents: stripeCents,
      hostCents: host < 0 ? 0 : host,
    );
  }

  /// What to charge so [amountCents] reaches the host after both fees
  /// (chargeCoveringFees in packages/shared).
  int chargeCoveringFees(int amountCents) {
    if (amountCents <= 0) return amountCents;
    final rate = (platform.percentBps + card.percentBps) / 10000;
    var charge =
        ((amountCents + platform.fixedCents + card.fixedCents) / (1 - rate))
            .floor() -
        2;
    if (charge < amountCents) charge = amountCents;
    while (breakdown(charge).hostCents < amountCents) {
      charge++;
    }
    return charge;
  }

  /// Why [amountCents] can't be paid online, or null (onlinePaymentProblem).
  String? problem(int amountCents, String currency) {
    if (currency != 'USD') return 'Online payments are in US dollars only.';
    if (amountCents < 50 || platform.on(amountCents) >= amountCents) {
      return 'This fee is too small to pay online.';
    }
    return null;
  }
}
