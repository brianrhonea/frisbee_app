// Online payments: the host owner's payout card and the Pay button, with a
// fake PaymentRepository (the API's own tests cover Stripe and the
// webhook: apps/api/test/payments.test.ts).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/payment/payment_repository.dart';
import 'package:frisbee_app/domain/models/payments.dart';
import 'package:frisbee_app/ui/payments/widgets/payment_widgets.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:provider/provider.dart';

class _FakePayments implements PaymentRepository {
  PayoutAccount account = const PayoutAccount(
    available: true,
    status: PayoutStatus.none,
    feeLabel: r'1% + $1',
  );
  PayOptions options = const PayOptions(
    online: true,
    amountCents: 40000,
    feeCents: 500,
    feeLabel: r'1% + $1',
    paid: false,
  );
  PaymentFees feeAnswer = const PaymentFees(
    available: true,
    platform: PaymentFees.defaultPlatform,
    card: PaymentFees.defaultCard,
  );
  final calls = <String>[];

  @override
  Future<Result<PaymentFees>> fees() async => Result.ok(feeAnswer);

  @override
  Future<Result<PayoutAccount>> payouts(String teamId) async {
    calls.add('payouts $teamId');
    return Result.ok(account);
  }

  @override
  Future<Result<Uri>> payoutLink(String teamId) async {
    calls.add('link $teamId');
    return Result.ok(Uri.parse('https://connect.test/$teamId'));
  }

  @override
  Future<Result<PayOptions>> payOptions(
    String tournamentId, {
    String? teamId,
  }) async {
    calls.add('options $tournamentId ${teamId ?? 'me'}');
    return Result.ok(options);
  }

  @override
  Future<Result<Uri>> checkout(String tournamentId, {String? teamId}) async {
    calls.add('checkout $tournamentId ${teamId ?? 'me'}');
    return Result.ok(Uri.parse('https://checkout.test/$tournamentId'));
  }
}

void main() {
  late _FakePayments payments;
  late List<Uri> opened;

  Future<bool> open(Uri url) async {
    opened.add(url);
    return true;
  }

  setUp(() {
    payments = _FakePayments();
    opened = [];
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      Provider<PaymentRepository>.value(
        value: payments,
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('payouts card', () {
    testWidgets('offers Stripe with the fee, and opens its page', (
      tester,
    ) async {
      await pump(tester, PayoutsCard(teamId: 'host', open: open));
      expect(find.text('Take payments online'), findsOneWidget);
      expect(find.textContaining(r'Stall 10 keeps 1% + $1'), findsOneWidget);
      await tester.tap(find.text('Set up with Stripe'));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://connect.test/host')]);
    });

    testWidgets('asks to finish, then says it is on', (tester) async {
      payments.account = const PayoutAccount(
        available: true,
        status: PayoutStatus.pending,
        feeLabel: r'1% + $1',
      );
      await pump(tester, PayoutsCard(teamId: 'host', open: open));
      expect(find.text('Continue with Stripe'), findsOneWidget);
      payments.account = const PayoutAccount(
        available: true,
        status: PayoutStatus.ready,
        feeLabel: r'1% + $1',
      );
      await pump(tester, PayoutsCard(key: UniqueKey(), teamId: 'host'));
      expect(find.text('Online payments are on'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('hides while payments are off, or without a repository', (
      tester,
    ) async {
      payments.account = PayoutAccount.unavailable;
      await pump(tester, const PayoutsCard(teamId: 'host'));
      expect(find.byType(Card), findsNothing);
      await tester.pumpWidget(
        const MaterialApp(home: PayoutsCard(teamId: 'host')),
      );
      expect(find.byType(Card), findsNothing);
    });
  });

  group('pay button', () {
    testWidgets("pays a team's fee through Checkout", (tester) async {
      await pump(
        tester,
        PayOnlineButton(tournamentId: 't1', teamId: 'haze', open: open),
      );
      expect(payments.calls, ['options t1 haze']);
      await tester.tap(find.text(r'Pay $400 online'));
      await tester.pumpAndSettle();
      expect(payments.calls.last, 'checkout t1 haze');
      expect(opened, [Uri.parse('https://checkout.test/t1')]);
    });

    testWidgets("pays the player's own entry fee", (tester) async {
      payments.options = const PayOptions(
        online: true,
        amountCents: 6000,
        feeCents: 160,
        feeLabel: r'1% + $1',
        paid: false,
      );
      await pump(tester, PayOnlineButton(tournamentId: 'hat', open: open));
      await tester.tap(find.text(r'Pay $60 online'));
      await tester.pumpAndSettle();
      expect(payments.calls.last, 'checkout hat me');
    });

    testWidgets("shows nothing when the host doesn't take payments", (
      tester,
    ) async {
      payments.options = const PayOptions(
        online: false,
        amountCents: 40000,
        feeCents: 500,
        feeLabel: r'1% + $1',
        paid: false,
        reason: 'The host collects fees themselves.',
      );
      await pump(tester, const PayOnlineButton(tournamentId: 't1'));
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('fee breakdown for hosts', () {
    test(r'splits $100 into $2, $3.20 and $94.80 (same as the API)', () {
      const fees = PaymentFees(
        available: true,
        platform: PaymentFees.defaultPlatform,
        card: PaymentFees.defaultCard,
      );
      final b = fees.breakdown(10000);
      expect(b.platformCents, 200);
      expect(b.stripeCents, 320);
      expect(b.hostCents, 9480);
      // packages/shared/test/payments.test.ts uses the same cases.
      final odd = fees.breakdown(3750);
      expect(
        (odd.platformCents, odd.stripeCents, odd.hostCents),
        (138, 139, 3473),
      );
      expect(fees.breakdown(100).hostCents, 0);
      expect(PaymentFees.defaultCard.label, r'2.9% + $0.30');
      expect(PaymentFees.defaultPlatform.label, r'1% + $1');
    });

    testWidgets('the form note says what the host gets', (tester) async {
      await pump(
        tester,
        const FeeBreakdownNote(amountCents: 10000, currency: 'USD'),
      );
      expect(
        find.text(
          r'Paid online in Stall 10, you get about $94.80 of each $100. '
          r'Stall 10 keeps $2 (1% + $1) and Stripe about $3.20 '
          r'(2.9% + $0.30, its usual card fee). Paid your own way, you keep '
          'it all.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('says why a fee can\'t be paid online', (tester) async {
      await pump(
        tester,
        const FeeBreakdownNote(amountCents: 10000, currency: 'CAD'),
      );
      expect(
        find.text('Online payments are in US dollars only.'),
        findsOneWidget,
      );
      await pump(
        tester,
        FeeBreakdownNote(key: UniqueKey(), amountCents: 100, currency: 'USD'),
      );
      expect(find.text('This fee is too small to pay online.'), findsOneWidget);
    });

    testWidgets('says nothing while payments are off', (tester) async {
      payments.feeAnswer = PaymentFees.unavailable;
      await pump(
        tester,
        const FeeBreakdownNote(amountCents: 10000, currency: 'USD'),
      );
      expect(find.byKey(const Key('fee-breakdown')), findsNothing);
    });

    testWidgets("the payout card uses the event's fee", (tester) async {
      await pump(tester, const PayoutsCard(teamId: 'host', amountCents: 40000));
      expect(
        find.text(
          r'On a $400 fee you get about $383.10: Stall 10 keeps $5 and '
          r'Stripe about $11.90.',
        ),
        findsOneWidget,
      );
    });
  });

  test('amounts read as dollars', () {
    expect(centsLabel(40000), r'$400');
    expect(centsLabel(160), r'$1.60');
  });
}
