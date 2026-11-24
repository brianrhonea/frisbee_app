// Online payments for tournament and league fees. Stall 10 takes each
// payment and sends the host its fee once the event is over. The server's
// answers, as in packages/shared/src/payments.ts.

/// Told to organizers and payers: when hosts get paid, and what a refund
/// returns (payoutTimingNote, refundPolicyNote in packages/shared).
/// On the host's payouts card (payoutReviewNote in packages/shared).
const payoutReviewNote =
    "Stall 10 checks your first payout, and an event's payouts once they "
    "pass \$2,000, before they're sent.";

/// The API's answer when payouts are set up or changed without a sign-in
/// in the last 15 minutes (payoutsReauthMessage in packages/shared): the
/// app asks the owner to confirm it's them, then tries again.
const payoutsReauthMessage =
    "For your security, confirm it's you before setting up or changing "
    'payouts.';

const payoutTimingNote =
    'Fees paid online are held by Stall 10 and sent to the host a few days '
    'after the event is over.';
const refundPolicyNote =
    "A refund returns the fee. The service and processing fees aren't "
    'refunded.';

/// One fee paid online, as the host's earnings list it.
enum EarningsStatus {
  held('Held until the event is over'),
  sent('Sent'),
  kept('Stall 10 event'),
  refunded('Refunded'),
  disputed('Disputed');

  const EarningsStatus(this.label);
  final String label;

  static EarningsStatus parse(Object? v) =>
      values.firstWhere((s) => s.name == v, orElse: () => held);
}

class EarningsItem {
  const EarningsItem({
    required this.tournamentId,
    required this.label,
    required this.amountCents,
    required this.status,
    this.at,
  });

  final String tournamentId;

  /// The receipt line, e.g. "Bid fee: Spring Fling (Haze)".
  final String label;
  final int amountCents;
  final EarningsStatus status;
  final DateTime? at;

  factory EarningsItem.fromMap(Map<String, Object?> m) => EarningsItem(
    tournamentId: m['tournamentId'] as String? ?? '',
    label: m['label'] as String? ?? 'Fee paid online',
    amountCents: (m['amountCents'] as num?)?.toInt() ?? 0,
    status: EarningsStatus.parse(m['status']),
    at: DateTime.tryParse(m['at'] as String? ?? ''),
  );
}

/// The host's fees paid online (`GET /v1/teams/:id/earnings`).
class Earnings {
  const Earnings({
    this.heldCents = 0,
    this.sentCents = 0,
    this.refundedCents = 0,
    this.disputedCents = 0,
    this.owedCents = 0,
    this.items = const [],
  });

  static const none = Earnings();

  final int heldCents;
  final int sentCents;
  final int refundedCents;
  final int disputedCents;

  /// Taken back after a refund or dispute but not recovered yet: comes off
  /// the next payout.
  final int owedCents;
  final List<EarningsItem> items;

  bool get isEmpty => items.isEmpty && owedCents == 0;

  factory Earnings.fromMap(Map<String, Object?> m) {
    int c(String k) => (m[k] as num?)?.toInt() ?? 0;
    return Earnings(
      heldCents: c('heldCents'),
      sentCents: c('sentCents'),
      refundedCents: c('refundedCents'),
      disputedCents: c('disputedCents'),
      owedCents: c('owedCents'),
      items: [
        for (final i in (m['items'] as List?) ?? const [])
          if (i is Map) EarningsItem.fromMap(i.cast<String, Object?>()),
      ],
    );
  }
}

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
    this.canSetUp = true,
    this.ownerName = '',
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

  /// The caller can start or finish setup (the host's owner); other
  /// managers see the status and [ownerName] to ask.
  final bool canSetUp;
  final String ownerName;

  factory PayoutAccount.fromMap(Map<String, Object?> m) => PayoutAccount(
    available: m['available'] == true,
    status: PayoutStatus.parse(m['status']),
    feeLabel: m['feeLabel'] as String? ?? '',
    canSetUp: m['canSetUp'] != false,
    ownerName: m['ownerName'] as String? ?? 'the owner',
  );
}

/// The app's payment sheet for one fee (`POST /v1/tournaments/:id/pay/intent`;
/// PaymentIntentResult in packages/shared).
class PaymentSheetRequest {
  const PaymentSheetRequest({
    required this.clientSecret,
    required this.account,
    required this.merchantName,
    required this.amountCents,
    required this.currency,
  });

  final String clientSecret;

  /// null: the payment is made on Stall 10's own account (API 0.47.0);
  /// before that, the host's account (a direct charge).
  final String? account;

  /// Who takes the payment, on the sheet: "Stall 10".
  final String merchantName;
  final int amountCents;
  final String currency;

  factory PaymentSheetRequest.fromMap(Map<String, Object?> m) =>
      PaymentSheetRequest(
        clientSecret: m['clientSecret'] as String? ?? '',
        account: switch (m['account']) {
          final String a when a.isNotEmpty => a,
          _ => null,
        },
        merchantName: m['merchantName'] as String? ?? 'Stall 10',
        amountCents: (m['amountCents'] as num?)?.toInt() ?? 0,
        currency: m['currency'] as String? ?? 'USD',
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
    this.offlineAt,
  }) : chargeCents = chargeCents ?? amountCents;

  /// When the payer said they'll pay another way; null if they haven't.
  final DateTime? offlineAt;

  /// The host takes payments through Stall 10 and this fee can be paid online.
  final bool online;

  /// The fee the host set.
  final int amountCents;

  /// What paying online costs: [amountCents] plus [processingCents].
  final int chargeCents;

  /// Stall 10's and Stripe's fees, added to the fee (payers always pay them).
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
    offlineAt: DateTime.tryParse(m['offlineAt'] as String? ?? ''),
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

  /// 3% of the fee, paid by the payer (defaultPlatformFee).
  static const defaultPlatform = FeeRate(percentBps: 300, fixedCents: 0);

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

  /// What the payer is charged online for a fee of [amountCents]: the fee,
  /// Stall 10's fee on it, and Stripe's fee on the whole charge, so the
  /// full fee reaches the host (onlineCharge in packages/shared).
  int chargeCoveringFees(int amountCents) {
    if (amountCents <= 0) return amountCents;
    final ours = platform.on(amountCents);
    final rate = card.percentBps / 10000;
    var charge =
        ((amountCents + ours + card.fixedCents) / (1 - rate)).floor() - 2;
    if (charge < amountCents + ours) charge = amountCents + ours;
    while (charge - ours - card.on(charge) < amountCents) {
      charge++;
    }
    return charge;
  }

  /// Stall 10's fee on a fee of [amountCents], added to what the payer pays.
  int platformOn(int amountCents) =>
      amountCents <= 0 ? 0 : platform.on(amountCents);

  /// Why [amountCents] can't be paid online, or null (onlinePaymentProblem).
  String? problem(int amountCents, String currency) {
    if (currency != 'USD') return 'Online payments are in US dollars only.';
    if (amountCents < 50 || platform.on(amountCents) >= amountCents) {
      return 'This fee is too small to pay online.';
    }
    return null;
  }
}
