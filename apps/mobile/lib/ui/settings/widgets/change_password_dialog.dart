import 'package:flutter/material.dart';

import '../../../utils/password_policy.dart';
import '../../../utils/result.dart';
import '../../auth/widgets/password_field.dart';
import '../../auth/widgets/password_strength_meter.dart';
import '../../core/ui/error_message.dart';
import '../../profile/view_models/profile_viewmodel.dart';

/// Current password, then the new one twice. Closes with true once changed.
class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key, required this.viewModel});

  final ProfileViewModel viewModel;

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  ProfileViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.changePassword.clearResult();
    vm.changePassword.addListener(_onChange);
    vm.sendPasswordReset.addListener(_onReset);
  }

  @override
  void dispose() {
    vm.changePassword.removeListener(_onChange);
    vm.sendPasswordReset.removeListener(_onReset);
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _onChange() {
    if (vm.changePassword.completed) {
      vm.changePassword.clearResult();
      Navigator.pop(context, true);
    } else {
      setState(() {});
    }
  }

  void _onReset() {
    final c = vm.sendPasswordReset;
    if (c.running) return;
    final email = vm.user?.email ?? 'your email';
    if (c.completed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('We sent a reset link to $email')));
    } else if (c.error) {
      showErrorSnackBar(context, c.result);
    }
    c.clearResult();
  }

  void _submit() {
    if (vm.changePassword.running) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    vm.changePassword.execute((_current.text, _next.text));
  }

  @override
  Widget build(BuildContext context) {
    final command = vm.changePassword;
    final busy = command.running;
    final failure = switch (command.result) {
      Error(:final error) => errorMessage(error),
      _ => null,
    };
    return AlertDialog(
      title: const Text('Change password'),
      scrollable: true,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PasswordField(
                  controller: _current,
                  label: 'Current password',
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      (v ?? '').isEmpty ? 'Enter your current password' : null,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: vm.sendPasswordReset.running
                        ? null
                        : vm.sendPasswordReset.execute,
                    child: const Text('Forgot it?'),
                  ),
                ),
                PasswordField(
                  controller: _next,
                  label: 'New password',
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    final p = v ?? '';
                    if (PasswordPolicy.problem(p) case final problem?) {
                      return problem;
                    }
                    if (p == _current.text) {
                      return 'Pick a password different from your current one';
                    }
                    return null;
                  },
                ),
                PasswordStrengthMeter(controller: _next),
                const SizedBox(height: 12),
                PasswordField(
                  controller: _confirm,
                  label: 'Confirm new password',
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) =>
                      v == _next.text ? null : "The passwords don't match",
                ),
                if (failure != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    failure,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : _submit,
          child: busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Change password'),
        ),
      ],
    );
  }
}
