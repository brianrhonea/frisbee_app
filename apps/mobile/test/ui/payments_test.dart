// Online payments: the host owner's payout card and the Pay button, with a
// fake PaymentRepository (the API's own tests cover Stripe and the
// webhook: apps/api/test/payments.test.ts).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/payment/payment_repository.dart';
import 'package:frisbee_app/data/services/payment_sheet_service.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/models/payments.dart';
import 'package:frisbee_app/ui/payments/widgets/payment_widgets.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:provider/provider.dart';

class _FakePayments implements PaymentRepository {
  PayoutAccount account = const PayoutAccount(
    available: true,
    status: PayoutStatus.none,
    feeLabel: '3%',
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

  /// When set, payOptions waits for it (a slow answer from Stripe).
  Completer<Result<PayOptions>>? pending;

  @override
  bool available = true;

  @override
  Future<Result<void>> payOffline(
    String tournamentId, {
    String? teamId,
    required bool offline,
  }) async {
    calls.add('offline $tournamentId ${teamId ?? 'me'} $offline');
    options = PayOptions(
      online: options.online,
      amountCents: options.amountCents,
      feeCents: options.feeCents,
      feeLabel: options.feeLabel,
      paid: false,
      offlineAt: offline ? DateTime(2026, 11, 22) : null,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> mark(
    String tournamentId,
    String payerId, {
    required bool paid,
    required String note,
  }) async {
    calls.add('mark $tournamentId $payerId $paid $note');
    return const Result.ok(null);
  }

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
    final wait = pending;
    if (wait != null) {
      pending = null;
      return wait.future;
    }
    return Result.ok(options);
  }

  @override
  Future<Result<Uri>> checkout(String tournamentId, {String? teamId}) async {
    calls.add('checkout $tournamentId ${teamId ?? 'me'}');
    return Result.ok(Uri.parse('https://checkout.test/$tournamentId'));
  }

  @override
  Future<Result<PaymentSheetRequest>> paymentSheet(
    String tournamentId, {
    String? teamId,
  }) async {
    calls.add('sheet $tournamentId ${teamId ?? 'me'}');
    return Result.ok(
      PaymentSheetRequest(
        clientSecret: 'pi_1_secret',
        account: 'acct_1',
        merchantName: 'Fling Crew',
        amountCents: options.chargeCents,
        currency: 'USD',
      ),
    );
  }
}

/// The payment sheet: [outcome] or [failure], recording what it showed.
class _FakeSheet implements PaymentSheetService {
  _FakeSheet({this.available = true});
  @override
  final bool available;
  PaymentSheetOutcome outcome = PaymentSheetOutcome.completed;
  String? failure;
  final shown = <PaymentSheetRequest>[];
  @override
  Future<PaymentSheetOutcome> present(PaymentSheetRequest request) async {
    shown.add(request);
    if (failure != null) throw PaymentSheetException(failure!);
    return outcome;
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

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    PaymentSheetService? sheet,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PaymentRepository>.value(value: payments),
          Provider<PaymentSheetService?>.value(value: sheet),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('payment sheet', () {
    testWidgets('pays in the app, then asks whether it went through', (
      tester,
    ) async {
      final sheet = _FakeSheet();
      await pump(
        tester,
        PayOnlineButton(tournamentId: 't1', teamId: 'haze', open: open),
        sheet: sheet,
      );
      payments.options = const PayOptions(
        online: false,
        amountCents: 40000,
        feeCents: 500,
        feeLabel: r'1% + $1',
        paid: true,
      );
      await tester.tap(find.text(r'Pay $400 online'));
      await tester.pumpAndSettle();
      expect(payments.calls, [
        'options t1 haze',
        'sheet t1 haze',
        'options t1 haze',
      ]);
      expect(sheet.shown.single.account, 'acct_1');
      expect(opened, isEmpty);
      expect(find.text(r'Pay $400 online'), findsNothing);
    });

    testWidgets('closing the sheet leaves the button', (tester) async {
      final sheet = _FakeSheet()..outcome = PaymentSheetOutcome.canceled;
      await pump(
        tester,
        PayOnlineButton(tournamentId: 't1', teamId: 'haze', open: open),
        sheet: sheet,
      );
      await tester.tap(find.text(r'Pay $400 online'));
      await tester.pumpAndSettle();
      expect(payments.calls.last, 'sheet t1 haze');
      expect(find.text(r'Pay $400 online'), findsOneWidget);
    });

    testWidgets("a declined payment shows Stripe's message", (tester) async {
      final sheet = _FakeSheet()..failure = 'Your card was declined.';
      await pump(
        tester,
        PayOnlineButton(tournamentId: 't1', teamId: 'haze', open: open),
        sheet: sheet,
      );
      await tester.tap(find.text(r'Pay $400 online'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Your card was declined.'), findsOneWidget);
    });

    testWidgets('without a key, Checkout opens in the browser', (tester) async {
      await pump(
        tester,
        PayOnlineButton(tournamentId: 't1', teamId: 'haze', open: open),
        sheet: _FakeSheet(available: false),
      );
      await tester.tap(find.text(r'Pay $400 online'));
      await tester.pumpAndSettle();
      expect(payments.calls.last, 'checkout t1 haze');
      expect(opened, hasLength(1));
    });
  });

  test("Stripe's return link isn't a page", () {
    expect(isStripeReturn(Uri.parse(stripeReturnUrl)), isTrue);
    expect(isStripeReturn(Uri.parse('/safepay?x=1')), isTrue);
    expect(isStripeReturn(Uri.parse('stall10://open/join/ABC')), isFalse);
    expect(isStripeReturn(Uri.parse('/teams/t1')), isFalse);
  });

  group('payouts card', () {
    testWidgets('offers Stripe with the fee, and opens its page', (
      tester,
    ) async {
      await pump(tester, PayoutsCard(teamId: 'host', open: open));
      expect(find.text('Take payments online'), findsOneWidget);
      expect(
        find.textContaining("payers also pay Stall 10's 3% and Stripe's card fee"),
        findsOneWidget,
      );
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
    test(r'splits $100 into $3, $3.20 and the rest (same as the API)', () {
      const fees = PaymentFees(
        available: true,
        platform: PaymentFees.defaultPlatform,
        card: PaymentFees.defaultCard,
      );
      final b = fees.breakdown(10000);
      expect(b.platformCents, 300);
      expect(b.stripeCents, 320);
      expect(b.hostCents, 9380);
      // packages/shared/test/payments.test.ts uses the same cases.
      final odd = fees.breakdown(3750);
      expect(
        (odd.platformCents, odd.stripeCents, odd.hostCents),
        (113, 139, 3498),
      );
      expect(fees.breakdown(30).hostCents, 0);
      expect(PaymentFees.defaultCard.label, r'2.9% + $0.30');
      expect(PaymentFees.defaultPlatform.label, '3%');
    });

    testWidgets('the form note says payers pay the fees and the host gets it '
        'all', (tester) async {
      await pump(
        tester,
        const FeeBreakdownNote(amountCents: 10000, currency: 'USD'),
      );
      expect(
        find.text(
          r'Paid online, they pay $106.39: $100, plus $3 for Stall 10 (3%) '
          r"and about $3.39 for Stripe's card fee. You get the whole $100. "
          r'Paid your own way, they pay $100.',
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
          r'On a $400 fee, payers pay $424.61 online and you get the whole '
          r'$400.',
        ),
        findsOneWidget,
      );
    });
  });

  group('payers pay the fees', () {
    const fees = PaymentFees(
      available: true,
      platform: PaymentFees.defaultPlatform,
      card: PaymentFees.defaultCard,
    );

    test('charge leaves the host the whole fee (same as the API)', () {
      // packages/shared/test/payments.test.ts uses the same cases.
      expect(fees.chargeCoveringFees(10000), 10639);
      expect(fees.chargeCoveringFees(40000), 42461);
      expect(fees.platformOn(40000), 1200);
      for (final amount in [50, 999, 3750, 6000, 10000, 40000, 123457]) {
        final charge = fees.chargeCoveringFees(amount);
        final host = charge - fees.platformOn(amount) - fees.card.on(charge);
        expect(host, greaterThanOrEqualTo(amount));
        expect(host, lessThanOrEqualTo(amount + 1));
      }
    });

    testWidgets('the Pay button shows the total and the fees', (tester) async {
      payments.options = const PayOptions(
        online: true,
        amountCents: 10000,
        chargeCents: 10639,
        processingCents: 639,
        feeCents: 300,
        feeLabel: '3%',
        paid: false,
      );
      await pump(tester, PayOnlineButton(tournamentId: 't1', open: open));
      expect(find.text(r'Pay $106.39 online'), findsOneWidget);
      expect(
        find.textContaining(r'Includes $6.39 in service and processing fees.'),
        findsOneWidget,
      );
    });

    testWidgets("the host form has no switch for it", (tester) async {
      expect(find.byKey(const Key('payer-covers-fees')), findsNothing);
    });
  });

  group('after paying', () {
    testWidgets('a bank payment shows as processing, with no Pay button', (
      tester,
    ) async {
      payments.options = const PayOptions(
        online: false,
        amountCents: 40000,
        feeCents: 500,
        feeLabel: r'1% + $1',
        paid: false,
        processing: true,
        reason:
            'Your bank payment is processing. It can take up to 4 business '
            'days.',
      );
      await pump(tester, const PayOnlineButton(tournamentId: 't1'));
      expect(find.byType(FilledButton), findsNothing);
      expect(
        find.textContaining('Your bank payment is processing'),
        findsOneWidget,
      );
    });

    testWidgets('coming back checks the payment instead of offering Pay', (
      tester,
    ) async {
      await pump(
        tester,
        PayOnlineButton(tournamentId: 't1', teamId: 'haze', open: open),
      );
      await tester.tap(find.text(r'Pay $400 online'));
      await tester.pumpAndSettle();
      // Back from Stripe: the reload hangs until Stripe answers.
      final answer = Completer<Result<PayOptions>>();
      payments.pending = answer;
      payments.options = const PayOptions(
        online: false,
        amountCents: 40000,
        feeCents: 500,
        feeLabel: r'1% + $1',
        paid: true,
      );
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(find.text('Checking your payment…'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      answer.complete(Result.ok(payments.options));
      await tester.pumpAndSettle();
      expect(find.text('Checking your payment…'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  testWidgets(
    'a failed check after paying hides Pay and offers to check again',
    (tester) async {
      await pump(
        tester,
        PayOnlineButton(tournamentId: 't1', teamId: 'haze', open: open),
      );
      await tester.tap(find.text(r'Pay $400 online'));
      await tester.pumpAndSettle();
      final answer = Completer<Result<PayOptions>>();
      payments.pending = answer;
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      answer.complete(Result.error(Exception('offline')));
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsNothing);
      expect(
        find.textContaining("Couldn't check your payment"),
        findsOneWidget,
      );
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(find.text(r'Pay $400 online'), findsOneWidget);
    },
  );

  group('paying another way', () {
    testWidgets("a payer says they'll pay by check, then takes it back", (
      tester,
    ) async {
      await pump(
        tester,
        PayOnlineButton(tournamentId: 't1', teamId: 'haze', open: open),
      );
      await tester.tap(find.text("We'll pay another way"));
      await tester.pumpAndSettle();
      expect(payments.calls, contains('offline t1 haze true'));
      expect(
        find.textContaining("You told the host you'll pay another way"),
        findsOneWidget,
      );
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(payments.calls, contains('offline t1 haze false'));
      expect(find.text("We'll pay another way"), findsOneWidget);
    });

    testWidgets('offered even when the host takes no online payments', (
      tester,
    ) async {
      payments.options = const PayOptions(
        online: false,
        amountCents: 40000,
        feeCents: 500,
        feeLabel: r'1% + $1',
        paid: false,
        reason: "The host doesn't take payments through Stall 10.",
      );
      await pump(tester, const PayOnlineButton(tournamentId: 't1'));
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text("We'll pay another way"), findsOneWidget);
    });

    test("the host's lists say who is paying another way", () {
      expect(
        paymentStatusLabel(
          EntryPayment(teamId: 'haze', offlineAt: DateTime(2026)),
          overdue: true,
        ),
        'Paying another way',
      );
      expect(
        paymentStatusLabel(const EntryPayment(teamId: 'haze'), overdue: true),
        'Overdue',
      );
      expect(
        paymentStatusLabel(
          EntryPayment(teamId: 'haze', paid: true, offlineAt: DateTime(2026)),
          overdue: false,
        ),
        'Paid',
      );
    });
  });

  test('amounts read as dollars', () {
    expect(centsLabel(40000), r'$400');
    expect(centsLabel(160), r'$1.60');
  });
}
