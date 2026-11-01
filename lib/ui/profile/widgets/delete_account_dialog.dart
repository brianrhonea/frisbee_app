import 'package:flutter/material.dart';

import '../../../domain/models/app_user.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../view_models/profile_viewmodel.dart';

/// The word the user types to confirm deleting their account.
const deleteConfirmWord = 'DELETE';

/// Asks the user to confirm deleting their account: says what goes, has
/// them type [deleteConfirmWord], and confirms it's them (their password,
/// or signing in again with Google or Apple). Runs the deletion and shows
/// any error here; once it's done the app returns to sign-in.
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key, required this.viewModel});

  final ProfileViewModel viewModel;

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  ProfileViewModel get vm => widget.viewModel;
  final _word = TextEditingController();
  final _password = TextEditingController();

  bool get _usesPassword => vm.reauthMethod == SignInMethod.password;

  bool get _ready =>
      _word.text.trim() == deleteConfirmWord &&
      (!_usesPassword || _password.text.isNotEmpty);

  @override
  void initState() {
    super.initState();
    vm.deleteAccount.clearResult();
  }

  @override
  void dispose() {
    _word.dispose();
    _password.dispose();
    super.dispose();
  }

  void _delete() {
    if (!_ready || vm.deleteAccount.running) return;
    vm.deleteAccount.execute(_usesPassword ? _password.text : null);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final provider = switch (vm.reauthMethod) {
      SignInMethod.google => 'Google',
      SignInMethod.apple => 'Apple',
      _ => null,
    };
    return ListenableBuilder(
      listenable: vm.deleteAccount,
      builder: (context, _) {
        final running = vm.deleteAccount.running;
        final error = vm.deleteAccount.error ? vm.deleteAccount.result : null;
        return AlertDialog(
          title: const Text('Delete your account?'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This permanently deletes your account and everything '
                    "you've added. It can't be undone.",
                  ),
                  const SizedBox(height: 12),
                  for (final item in const [
                    'Your profile, stats links and settings',
                    'Your posts, and the messages you sent in team chats, '
                        'meetings and direct messages, with their photos '
                        'and files',
                    'Your RSVPs, reactions, poll votes and join requests',
                    'Your place on every team and group. Teams you own '
                        'pass to a coach or captain (or another member); a '
                        'team with nobody else on it is deleted.',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2, right: 8),
                            child: Icon(
                              Icons.remove_circle_outline,
                              size: 16,
                              color: scheme.error,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              item,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Messages others sent you stay with them, from '
                    '"Deleted user".',
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _word,
                    enabled: !running,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Type $deleteConfirmWord to confirm',
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _delete(),
                  ),
                  if (_usesPassword) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      enabled: !running,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Your password',
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _delete(),
                    ),
                  ] else if (provider != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      "You'll sign in with $provider again to confirm it's "
                      'you.',
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorMessage(error),
                      style: TextStyle(fontSize: 13, color: scheme.error),
                    ),
                  ],
                  if (running) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 6),
                    Text(
                      'Deleting your account. This can take a minute.',
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: running ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: _ready && !running ? _delete : null,
              child: const Text('Delete account'),
            ),
          ],
        );
      },
    );
  }
}
