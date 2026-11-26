import 'package:flutter/material.dart';

import '../view_models/verify_email_viewmodel.dart';
import 'auth_layout.dart';

/// "Verify your email": shown when a write was refused because the email
/// isn't verified. Resend the email, then "I've verified" to carry on.
class VerifyEmailScreen extends StatelessWidget {
  const VerifyEmailScreen({super.key, required this.viewModel});

  final VerifyEmailViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return AuthLayout(
      title: 'Verify your email',
      subtitle:
          'We sent a link to ${vm.email ?? 'your email address'}. Open it, '
          'then come back here and tap “I\'ve verified”.',
      child: ListenableBuilder(
        listenable: Listenable.merge([vm, vm.send, vm.check, vm.signOut]),
        builder: (context, _) {
          final busy =
              vm.send.running || vm.check.running || vm.signOut.running;
          final scheme = Theme.of(context).colorScheme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (vm.stillUnverified)
                _note(
                  const Key('verify-email-still'),
                  "We can't see that yet. Open the link in the email we sent, "
                  'then try again.',
                  scheme.error,
                ),
              if (vm.check.error)
                _note(
                  const Key('verify-email-check-error'),
                  "Couldn't check. Check your connection and try again.",
                  scheme.error,
                ),
              if (vm.send.error)
                _note(
                  const Key('verify-email-send-error'),
                  "Couldn't send the email. Wait a moment and try again.",
                  scheme.error,
                ),
              if (vm.send.completed)
                _note(
                  const Key('verify-email-sent'),
                  'Email sent. Check your inbox and spam folder.',
                  scheme.onSurfaceVariant,
                ),
              FilledButton(
                key: const Key('verify-email-check'),
                onPressed: busy ? null : vm.check.execute,
                child: vm.check.running
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("I've verified"),
              ),
              const SizedBox(height: 4),
              TextButton(
                key: const Key('verify-email-resend'),
                onPressed: busy ? null : vm.send.execute,
                child: const Text('Resend email'),
              ),
              TextButton(
                key: const Key('verify-email-sign-out'),
                onPressed: busy ? null : vm.signOut.execute,
                child: const Text('Sign out'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _note(Key key, String text, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      key: key,
      style: TextStyle(color: color),
    ),
  );
}
