import '../../core/themes/theme.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/app_user.dart';
import '../../../domain/models/personal_details.dart';
import '../../core/ui/error_message.dart';
import '../view_models/adults_only_viewmodel.dart';
import 'auth_layout.dart';

/// Shown instead of the app when the birth date is under 18: no form, no
/// retry. Sign out or delete the account are the only ways on.
class AdultsOnlyScreen extends StatelessWidget {
  const AdultsOnlyScreen({super.key, required this.viewModel});

  final AdultsOnlyViewModel viewModel;

  Future<void> _confirmDelete(BuildContext context) async {
    final password = TextEditingController();
    final usesPassword = viewModel.reauthMethod == SignInMethod.password;
    final go = await showDialog<bool>(
      context: context,
      animationStyle: AppMotion.dialogStyle(context),
      builder: (context) => AlertDialog(
        title: const Text('Delete account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Delete your account and its data? This can't be undone.",
            ),
            if (usesPassword) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('adults-only-password'),
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm your password',
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('adults-only-confirm-delete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, delete my account'),
          ),
        ],
      ),
    );
    // Not disposed here: the dialog is still animating out.
    if (go == true) {
      await viewModel.deleteAccount.execute(
        usesPassword ? password.text : null,
      );
    }
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: 'Stall 10 is for players 18 and older',
    subtitle: adultOnlyMessage,
    child: ListenableBuilder(
      listenable: Listenable.merge([
        viewModel.signOut,
        viewModel.deleteAccount,
      ]),
      builder: (context, _) {
        final busy =
            viewModel.signOut.running || viewModel.deleteAccount.running;
        final failed =
            viewModel.deleteAccount.error &&
            !isSignInCancelled(viewModel.deleteAccount.result);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (failed) ...[
              Text(
                "Couldn't delete the account. Sign in again and retry, or "
                'email $supportEmail.',
                key: const Key('adults-only-delete-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              key: const Key('adults-only-sign-out'),
              onPressed: busy ? null : viewModel.signOut.execute,
              child: const Text('Sign out'),
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const Key('adults-only-delete'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: busy ? null : () => _confirmDelete(context),
              child: const Text('Delete account'),
            ),
          ],
        );
      },
    ),
  );
}
