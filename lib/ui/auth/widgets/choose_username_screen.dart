import 'package:flutter/material.dart';

import '../../core/ui/error_message.dart';
import '../view_models/choose_username_viewmodel.dart';
import 'auth_layout.dart';
import 'username_field.dart';

/// "Pick your username", before anything else, for people who signed up
/// with Google or Apple or before usernames existed.
class ChooseUsernameScreen extends StatefulWidget {
  const ChooseUsernameScreen({super.key, required this.viewModel});

  final ChooseUsernameViewModel viewModel;

  @override
  State<ChooseUsernameScreen> createState() => _ChooseUsernameScreenState();
}

class _ChooseUsernameScreenState extends State<ChooseUsernameScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _username = TextEditingController(text: vm.suggestion);

  ChooseUsernameViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.claim.addListener(_onResult);
    if (_username.text.isNotEmpty) vm.username.update(_username.text);
  }

  @override
  void dispose() {
    vm.claim.removeListener(_onResult);
    _username.dispose();
    super.dispose();
  }

  void _onResult() {
    final cmd = vm.claim;
    if (cmd.error) {
      showErrorSnackBar(context, cmd.result);
      cmd.clearResult();
      _formKey.currentState?.validate();
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    vm.claim.execute(_username.text);
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: vm.name.isEmpty
        ? 'Pick your username'
        : 'Welcome, ${vm.name}. Pick your username',
    subtitle:
        "It's how teammates find and message you, as @name. Only one "
        'person can have each.',
    child: ListenableBuilder(
      listenable: Listenable.merge([vm.claim, vm.signOut]),
      builder: (context, _) {
        final busy = vm.claim.running || vm.signOut.running;
        return Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UsernameField(
                controller: _username,
                checker: vm.username,
                autofocus: true,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy ? null : _submit,
                child: vm.claim.running
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Continue'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: busy ? null : vm.signOut.execute,
                child: const Text('Sign out'),
              ),
            ],
          ),
        );
      },
    ),
  );
}
