import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/services/payment_sheet_service.dart';
import 'package:frisbee_app/domain/models/payments.dart';

const _request = PaymentSheetRequest(
  clientSecret: 'pi_123_secret_abc',
  account: null,
  merchantName: 'Stall 10',
  amountCents: 1236,
  currency: 'usd',
);

void main() {
  group('buildPaymentSheetParameters', () {
    test('passes the intent and merchant through, with the return link', () {
      final p = buildPaymentSheetParameters(_request, production: false);
      expect(p.paymentIntentClientSecret, 'pi_123_secret_abc');
      expect(p.merchantDisplayName, 'Stall 10');
      expect(p.returnURL, stripeReturnUrl);
    });

    test('allows no delayed payment methods, so no US bank payments', () {
      final p = buildPaymentSheetParameters(_request, production: true);
      expect(p.allowsDelayedPaymentMethods, isFalse);
    });

    test('Google Pay is on, in the test environment unless production', () {
      final dev = buildPaymentSheetParameters(_request, production: false);
      expect(dev.googlePay, isNotNull);
      expect(dev.googlePay!.merchantCountryCode, 'US');
      expect(dev.googlePay!.currencyCode, 'USD');
      expect(dev.googlePay!.testEnv, isTrue);

      final prod = buildPaymentSheetParameters(_request, production: true);
      expect(prod.googlePay!.testEnv, isFalse);
    });

    test('Google Pay falls back to USD when the currency is missing', () {
      final p = buildPaymentSheetParameters(
        PaymentSheetRequest.fromMap({'clientSecret': 's', 'currency': ''}),
        production: false,
      );
      expect(p.googlePay!.currencyCode, 'USD');
    });

    test('Apple Pay is off without a merchant ID', () {
      final p = buildPaymentSheetParameters(_request, production: false);
      expect(p.applePay, isNull);
    });

    test('Apple Pay is on with a merchant ID', () {
      final p = buildPaymentSheetParameters(
        _request,
        production: false,
        appleMerchantId: 'merchant.app.stall10',
      );
      expect(p.applePay, isNotNull);
      expect(p.applePay!.merchantCountryCode, 'US');
    });

    test('a host account on an older payment changes nothing here', () {
      final p = buildPaymentSheetParameters(
        PaymentSheetRequest.fromMap({'clientSecret': 's', 'account': 'acct_1'}),
        production: false,
      );
      expect(p.allowsDelayedPaymentMethods, isFalse);
      expect(p.googlePay, isNotNull);
    });
  });

  group('StripePaymentSheetService', () {
    test('is not available without a publishable key', () {
      expect(StripePaymentSheetService(publishableKey: '').available, isFalse);
    });

    test('defaults to the test environment in a dev build', () {
      // FIREBASE_ENV is not "prod" under flutter test.
      expect(StripePaymentSheetService().production, isFalse);
    });
  });
}
