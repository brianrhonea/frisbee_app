import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../data/repositories/payment/payment_repository.dart';
import '../../../utils/invite_links.dart';
import '../../../utils/result.dart';

/// Stripe's payments setup inside the app: the website's `/embed/payouts`
/// page (Stripe's embedded onboarding) in a WebView, so the owner never
/// leaves Stall 10. Stripe has no Flutter version of its Connect
/// components, so the website hosts them.
///
///   page → app   Stall10Payouts.postMessage("ready" | "exit" | "error")
///   app → page   `window.stall10StartPayouts("<client secret>")`
///
/// The session's client secret comes from the API
/// ([PaymentRepository.payoutSession]) and goes to the page through the
/// channel, never in the URL, so the page needs no website sign-in.
/// Pops with true once the person finishes or closes Stripe's form.
class PayoutsSetupScreen extends StatefulWidget {
  const PayoutsSetupScreen({
    super.key,
    required this.payments,
    required this.teamId,
  });

  final PaymentRepository payments;
  final String teamId;

  /// Opens it full screen; true when Stripe's form was finished or closed.
  static Future<bool> open(
    BuildContext context, {
    required PaymentRepository payments,
    required String teamId,
  }) async =>
      await Navigator.of(context, rootNavigator: true).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => PayoutsSetupScreen(payments: payments, teamId: teamId),
        ),
      ) ??
      false;

  @override
  State<PayoutsSetupScreen> createState() => _PayoutsSetupScreenState();
}

class _PayoutsSetupScreenState extends State<PayoutsSetupScreen> {
  late final WebViewController _web;
  String? _error;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('Stall10Payouts', onMessageReceived: _onMessage)
      ..loadRequest(Uri.https(InviteLinks.host, '/embed/payouts'));
  }

  Future<void> _onMessage(JavaScriptMessage m) async {
    switch (m.message) {
      case 'ready':
        if (_started) return;
        _started = true;
        final r = await widget.payments.payoutSession(widget.teamId);
        if (!mounted) return;
        switch (r) {
          case Ok(:final value):
            await _web.runJavaScript(
              'window.stall10StartPayouts(${jsonEncode(value)})',
            );
          case Error(:final error):
            setState(() => _error = _message(error));
        }
      case 'exit':
        if (mounted) Navigator.of(context).pop(true);
      case 'error':
        if (mounted) {
          setState(
            () => _error = "Stripe's setup didn't open. Try again in a moment.",
          );
        }
    }
  }

  static String _message(Object e) {
    final text = '$e';
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(true),
        ),
        title: const Text('Set up payments'),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : WebViewWidget(controller: _web),
    );
  }
}
