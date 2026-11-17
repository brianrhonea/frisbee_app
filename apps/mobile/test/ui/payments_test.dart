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
  final calls = <String>[];

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

  test('amounts read as dollars', () {
    expect(centsLabel(40000), r'$400');
    expect(centsLabel(160), r'$1.60');
  });
}
