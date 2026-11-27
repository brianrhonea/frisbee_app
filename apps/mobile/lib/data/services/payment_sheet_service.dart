import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../domain/models/payments.dart';
import '../../firebase_options.dart';

/// What happened in the payment sheet.
enum PaymentSheetOutcome {
  /// Paid, or a bank payment sent off to clear.
  completed,

  /// The payer closed the sheet.
  canceled,
}

/// The app's own checkout: Stripe's PaymentSheet over the app, instead of
/// Stripe's Checkout page in the browser. Needs Stripe's publishable key
/// (`STRIPE_PUBLISHABLE_KEY` in the secrets file); without one, payments
/// open in the browser as before.
abstract class PaymentSheetService {
  /// Whether the sheet can be shown here.
  bool get available;

  /// Shows the sheet for [request]; throws [PaymentSheetException] when it
  /// couldn't be shown or the payment failed.
  Future<PaymentSheetOutcome> present(PaymentSheetRequest request);
}

/// A payment the sheet couldn't take, with Stripe's message for the payer.
class PaymentSheetException implements Exception {
  const PaymentSheetException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The link Stripe sends people back to after a bank or wallet page
/// (`stall10://open/safepay`); the router leaves it to Stripe
/// ([isStripeReturn]).
const stripeReturnUrl = 'stall10://open/safepay';

/// Whether [uri] is Stripe coming back to the sheet, not a page to open.
bool isStripeReturn(Uri uri) =>
    uri.host == 'safepay' ||
    (uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'safepay');

/// Hands Stripe's return link to the sheet (iOS; Android handles it itself).
Future<void> completeStripeReturn(Uri uri) async {
  try {
    final full = uri.scheme.isEmpty
        ? Uri.parse('$stripeReturnUrl${uri.hasQuery ? '?${uri.query}' : ''}')
        : uri;
    await Stripe.instance.handleURLCallback(full.toString());
  } catch (_) {
    // Not one Stripe was waiting for.
  }
}

/// The sheet's parameters for [request]: cards and one-tap wallets only.
///
/// - No delayed payment methods, so no US bank payments (they take days to
///   clear); a `processing` status is still handled where the payment is
///   shown.
/// - Google Pay always, in Google's test environment unless [production].
/// - Apple Pay only when [appleMerchantId] (the `STRIPE_MERCHANT_ID`
///   dart-define) is set: the iOS Apple Pay capability must be enabled in
///   the app's signing first.
SetupPaymentSheetParameters buildPaymentSheetParameters(
  PaymentSheetRequest request, {
  required bool production,
  String appleMerchantId = '',
}) {
  final currency = request.currency.toUpperCase();
  return SetupPaymentSheetParameters(
    paymentIntentClientSecret: request.clientSecret,
    merchantDisplayName: request.merchantName,
    allowsDelayedPaymentMethods: false,
    returnURL: stripeReturnUrl,
    googlePay: PaymentSheetGooglePay(
      merchantCountryCode: 'US',
      currencyCode: currency.isEmpty ? 'USD' : currency,
      testEnv: !production,
    ),
    applePay: appleMerchantId.isEmpty
        ? null
        : const PaymentSheetApplePay(merchantCountryCode: 'US'),
  );
}

class StripePaymentSheetService implements PaymentSheetService {
  StripePaymentSheetService({
    this.publishableKey = const String.fromEnvironment(
      'STRIPE_PUBLISHABLE_KEY',
    ),
    this.appleMerchantId = const String.fromEnvironment('STRIPE_MERCHANT_ID'),
    bool? production,
  }) : production =
           production ?? DefaultFirebaseOptions.env == FirebaseEnv.prod;

  final String publishableKey;

  /// Apple Pay's merchant ID (`merchant.…`, `STRIPE_MERCHANT_ID` in the
  /// secrets file); empty leaves Apple Pay off.
  final String appleMerchantId;

  /// Whether this is an App Store (prod) build: Google Pay's live
  /// environment instead of its test one.
  final bool production;

  @override
  bool get available =>
      publishableKey.isNotEmpty &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  Future<PaymentSheetOutcome> present(PaymentSheetRequest request) async {
    try {
      // Stall 10's own account (null), so a host's from an older payment
      // isn't left set.
      Stripe.publishableKey = publishableKey;
      Stripe.stripeAccountId = request.account;
      Stripe.urlScheme = 'stall10';
      if (appleMerchantId.isNotEmpty) {
        Stripe.merchantIdentifier = appleMerchantId;
      }
      await Stripe.instance.applySettings();
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: buildPaymentSheetParameters(
          request,
          production: production,
          appleMerchantId: appleMerchantId,
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      return PaymentSheetOutcome.completed;
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        return PaymentSheetOutcome.canceled;
      }
      throw PaymentSheetException(
        e.error.localizedMessage ??
            e.error.message ??
            "The payment didn't go through.",
      );
    } on StripeConfigException catch (_) {
      throw const PaymentSheetException("Couldn't open the payment sheet.");
    }
  }
}
