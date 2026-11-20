import 'package:flutter/material.dart';

import '../../../domain/models/person_name.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart' show Eyebrow, PersonAvatar;
import '../view_models/choose_username_viewmodel.dart';
import 'auth_layout.dart';
import 'username_field.dart';

/// "Your name and username", before anything else, for people who signed
/// up with Google or Apple or before usernames existed, and new accounts
/// without a name. The username follows the name until they edit it.
class ChooseUsernameScreen extends StatefulWidget {
  const ChooseUsernameScreen({super.key, required this.viewModel});

  final ChooseUsernameViewModel viewModel;

  @override
  State<ChooseUsernameScreen> createState() => _ChooseUsernameScreenState();
}

class _ChooseUsernameScreenState extends State<ChooseUsernameScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _first = TextEditingController(text: vm.prefillName.first);
  late final _last = TextEditingController(text: vm.prefillName.last);
  final _username = TextEditingController();

  /// The suggestion last put in the box; anything else is their own.
  String _suggested = '';
  bool _edited = false;

  ChooseUsernameViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.save.addListener(_onResult);
    _suggest();
    _username.addListener(() {
      if (_username.text != _suggested) _edited = true;
    });
    _first.addListener(_suggest);
    _last.addListener(_suggest);
  }

  /// Puts the name's suggestion in the username box, until they edit it.
  void _suggest() {
    if (_edited || !vm.needsUsername) return;
    final next = vm.suggestionFor(_first.text, _last.text);
    if (next == _username.text) return;
    _suggested = next;
    _username.text = next;
    vm.username.update(next);
  }

  @override
  void dispose() {
    vm.save.removeListener(_onResult);
    for (final c in [_first, _last, _username]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onResult() {
    final cmd = vm.save;
    if (cmd.error) {
      showErrorSnackBar(context, cmd.result);
      cmd.clearResult();
      _formKey.currentState?.validate();
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    vm.save.execute((
      firstName: _first.text,
      lastName: _last.text,
      username: _username.text,
    ));
  }

  static String? _required(String? v, String message) =>
      (v == null || v.trim().isEmpty) ? message : null;

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: vm.title,
    subtitle: vm.subtitle,
    child: ListenableBuilder(
      listenable: Listenable.merge([vm.save, vm.signOut]),
      builder: (context, _) {
        final busy = vm.save.running || vm.signOut.running;
        return Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (vm.asksName) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _first,
                          decoration: const InputDecoration(
                            labelText: 'First name',
                          ),
                          autofocus: true,
                          autofillHints: const [AutofillHints.givenName],
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          maxLength: PersonName.maxFirst,
                          buildCounter: _noCounter,
                          validator: (v) =>
                              _required(v, 'Enter your first name'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _last,
                          decoration: const InputDecoration(
                            labelText: 'Last name',
                          ),
                          autofillHints: const [AutofillHints.familyName],
                          textCapitalization: TextCapitalization.words,
                          textInputAction: vm.needsUsername
                              ? TextInputAction.next
                              : TextInputAction.done,
                          onFieldSubmitted: vm.needsUsername
                              ? null
                              : (_) => _submit(),
                          maxLength: PersonName.maxLast,
                          buildCounter: _noCounter,
                          validator: (v) =>
                              _required(v, 'Enter your last name'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (vm.needsUsername)
                  UsernameField(
                    controller: _username,
                    checker: vm.username,
                    autofocus: !vm.asksName,
                    onFieldSubmitted: (_) => _submit(),
                    hint: vm.asksName
                        ? 'Suggested from your name. Change it to anything '
                              'you like.'
                        : 'Letters, numbers, _ and . People find you by it.',
                  ),
                const SizedBox(height: 16),
                _Preview(first: _first, last: _last, username: _username),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy ? null : _submit,
                  child: vm.save.running
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Continue'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.of(context).muted,
                  ),
                  onPressed: busy ? null : vm.signOut.execute,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  static Widget? _noCounter(
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    required int? maxLength,
  }) => null;
}

/// "How teammates see you": the name and @username as they type them.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.first,
    required this.last,
    required this.username,
  });

  final TextEditingController first;
  final TextEditingController last;
  final TextEditingController username;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([first, last, username]),
    builder: (context, _) {
      final c = AppColors.of(context);
      final name = PersonName.join(first.text, last.text);
      final handle = username.text.trim();
      if (name.isEmpty && handle.isEmpty) return const SizedBox.shrink();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              PersonAvatar(name: name.isEmpty ? handle : name, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('How teammates see you'),
                    const SizedBox(height: 2),
                    if (name.isNotEmpty)
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                    if (handle.isNotEmpty)
                      Text(
                        '@$handle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: c.muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
