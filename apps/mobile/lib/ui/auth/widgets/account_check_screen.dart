import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/legal_links.dart';
import '../view_models/account_check_viewmodel.dart';
import 'auth_layout.dart';

/// Blocks the app when the account's sign-up checks couldn't be read: Try
/// again, Sign out, and the legal pages (which the app opens in the
/// browser) stay available.
class AccountCheckScreen extends StatelessWidget {
  const AccountCheckScreen({super.key, required this.viewModel});

  final AccountCheckViewModel viewModel;

  Future<void> _open(BuildContext context, Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Couldn't open $url")));
    }
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: "Couldn't check your account",
    subtitle:
        "We couldn't confirm a couple of things about your account, so we "
        "can't open the app yet. Check your connection and try again.",
    child: ListenableBuilder(
      listenable: Listenable.merge([
        viewModel,
        viewModel.retry,
        viewModel.signOut,
      ]),
      builder: (context, _) {
        final busy = viewModel.retry.running || viewModel.signOut.running;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (viewModel.retriedAndFailed && !viewModel.retry.running) ...[
              Text(
                "Still couldn't check. Try again in a moment.",
                key: const Key('account-check-still-failing'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              key: const Key('account-check-retry'),
              onPressed: busy ? null : viewModel.retry.execute,
              child: viewModel.retry.running
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Try again'),
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const Key('account-check-sign-out'),
              onPressed: busy ? null : viewModel.signOut.execute,
              child: const Text('Sign out'),
            ),
            // A column, not a Wrap: AuthLayout sizes by intrinsic height.
            for (final (label, url) in [
              ('Terms of Service', LegalLinks.terms),
              ('Privacy Policy', LegalLinks.privacy),
              ('Community Guidelines', LegalLinks.guidelines),
            ])
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => _open(context, url),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(label),
                ),
              ),
          ],
        );
      },
    ),
  );
}
