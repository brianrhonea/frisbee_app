import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/payment/payment_repository.dart';
import '../../../data/services/api_client.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/payments.dart';
import '../../../utils/invite_links.dart';
import '../../../utils/result.dart';
import '../../core/ui/error_message.dart';

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
/// [manage]: the linked account's bank details and payouts instead of
/// setup (`/embed/payouts?view=manage`).
///
/// Setting up or changing payouts needs a sign-in in the last 15 minutes
/// ([payoutsReauthMessage]); without one the owner confirms it's them here
/// (password, Google or Apple) and the setup carries on, as on the website
/// (ConfirmSignIn).
class PayoutsSetupScreen extends StatefulWidget {
  const PayoutsSetupScreen({
    super.key,
    required this.payments,
    required this.teamId,
    this.manage = false,
  });

  final PaymentRepository payments;
  final String teamId;
  final bool manage;

  /// Opens it full screen; true when Stripe's form was finished or closed.
  static Future<bool> open(
    BuildContext context, {
    required PaymentRepository payments,
    required String teamId,
    bool manage = false,
  }) async =>
      await Navigator.of(context, rootNavigator: true).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => PayoutsSetupScreen(
            payments: payments,
            teamId: teamId,
            manage: manage,
          ),
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

  /// The API wants a recent sign-in first.
  bool _reauth = false;
  bool _confirming = false;
  String? _reauthError;
  final _password = TextEditingController();

  AuthRepository? get _auth {
    try {
      return context.read<AuthRepository>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Only the website's payouts page loads at the top: the session's
      // secret is handed to nothing else. Stripe's forms run in frames
      // inside it.
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (r) =>
              !r.isMainFrame || _isPayoutsPage(Uri.tryParse(r.url))
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      )
      ..addJavaScriptChannel('Stall10Payouts', onMessageReceived: _onMessage)
      ..loadRequest(
        Uri.https(
          InviteLinks.host,
          '/embed/payouts',
          widget.manage ? const {'view': 'manage'} : null,
        ),
      );
  }

  /// The website's `/embed/payouts`, over HTTPS.
  static bool _isPayoutsPage(Uri? u) =>
      u != null &&
      u.scheme == 'https' &&
      u.host == InviteLinks.host &&
      u.path == '/embed/payouts';

  Future<void> _onMessage(JavaScriptMessage m) async {
    switch (m.message) {
      case 'ready':
        if (_started) return;
        // Asked by the page we loaded, not one it was replaced with.
        if (!_isPayoutsPage(Uri.tryParse(await _web.currentUrl() ?? ''))) {
          if (mounted) {
            setState(() => _error = "Stripe's setup didn't open. Try again.");
          }
          return;
        }
        _started = true;
        await _start();
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

  /// Asks the API for the setup session and hands it to the page.
  Future<void> _start() async {
    final r = await widget.payments.payoutSession(widget.teamId);
    if (!mounted) return;
    switch (r) {
      case Ok(:final value):
        await _web.runJavaScript(
          'window.stall10StartPayouts(${jsonEncode(value)})',
        );
      case Error(:final error):
        final reauth =
            error is ApiException &&
            error.message == payoutsReauthMessage &&
            _auth?.reauthMethod != null;
        setState(() {
          if (reauth) {
            _reauth = true;
          } else {
            _error = _message(error);
          }
        });
    }
  }

  Future<void> _confirm() async {
    final auth = _auth;
    if (auth == null) return;
    setState(() {
      _confirming = true;
      _reauthError = null;
    });
    final r = await auth.reauthenticate(password: _password.text);
    if (!mounted) return;
    switch (r) {
      case Ok():
        setState(() {
          _confirming = false;
          _reauth = false;
        });
        _password.clear();
        await _start();
      case Error(:final error):
        setState(() {
          _confirming = false;
          _reauthError = isSignInCancelled(error) ? null : errorMessage(error);
        });
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
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
        title: Text(
          widget.manage ? 'Bank account and payouts' : 'Set up payouts',
        ),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : _reauth
          ? _confirmView(context)
          : widget.manage
          ? WebViewWidget(controller: _web)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    payoutsSetupNote,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Expanded(child: WebViewWidget(controller: _web)),
              ],
            ),
    );
  }

  Widget _confirmView(BuildContext context) {
    final method = _auth?.reauthMethod;
    final password = method == SignInMethod.password;
    final label = switch (method) {
      SignInMethod.google => 'Continue with Google',
      SignInMethod.apple => 'Continue with Apple',
      _ => 'Confirm',
    };
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          payoutsReauthMessage,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        if (password) ...[
          TextField(
            key: const Key('payouts-reauth-password'),
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Your password'),
            onSubmitted: (_) => _confirming ? null : _confirm(),
          ),
          const SizedBox(height: 16),
        ],
        if (_reauthError != null) ...[
          Text(
            _reauthError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 12),
        ],
        FilledButton(
          key: const Key('payouts-reauth-confirm'),
          onPressed: _confirming ? null : _confirm,
          child: Text(_confirming ? 'Checking…' : label),
        ),
      ],
    );
  }
}
