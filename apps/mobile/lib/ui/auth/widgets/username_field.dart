import 'package:flutter/material.dart';

import '../../../domain/models/username.dart';
import '../view_models/username_checker.dart';

/// The username box: an "@" in front, and whether it's free as you type.
class UsernameField extends StatelessWidget {
  const UsernameField({
    super.key,
    required this.controller,
    required this.checker,
    this.autofocus = false,
    this.textInputAction,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final UsernameChecker checker;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: checker,
      builder: (context, _) {
        final status = checker.status;
        final ok = status == UsernameStatus.available;
        return TextFormField(
          controller: controller,
          autofocus: autofocus,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.newUsername],
          textInputAction: textInputAction,
          onChanged: checker.update,
          onFieldSubmitted: onFieldSubmitted,
          maxLength: Username.maxLength + 1,
          decoration: InputDecoration(
            labelText: 'Username',
            prefixText: '@',
            counterText: '',
            helperText: ok
                ? checker.message
                : status == UsernameStatus.empty
                ? 'Letters, numbers, _ and . People find you by it.'
                : null,
            helperStyle: ok ? TextStyle(color: colors.primary) : null,
            errorText: switch (status) {
              UsernameStatus.invalid ||
              UsernameStatus.taken ||
              UsernameStatus.failed => checker.message,
              _ => null,
            },
            suffixIcon: switch (status) {
              UsernameStatus.checking => const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              UsernameStatus.available => Icon(
                Icons.check_circle,
                color: colors.primary,
              ),
              UsernameStatus.taken || UsernameStatus.invalid => Icon(
                Icons.error_outline,
                color: colors.error,
              ),
              _ => null,
            },
          ),
          validator: (_) => switch (status) {
            UsernameStatus.available => null,
            UsernameStatus.empty => 'Pick a username',
            UsernameStatus.checking => 'Checking…',
            _ => checker.message,
          },
        );
      },
    );
  }
}
