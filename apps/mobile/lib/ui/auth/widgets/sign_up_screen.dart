import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/routes.dart';
import '../../../utils/password_policy.dart';
import '../../core/ui/error_message.dart';
import '../view_models/sign_up_viewmodel.dart';
import 'auth_layout.dart';
import 'password_field.dart';
import 'password_strength_meter.dart';
import 'username_field.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key, required this.viewModel});

  final SignUpViewModel viewModel;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  DateTime? _birth;

  SignUpViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.signUp.addListener(_onResult);
  }

  @override
  void dispose() {
    vm.signUp.removeListener(_onResult);
    for (final c in [_first, _last, _username, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onResult() {
    final cmd = vm.signUp;
    if (cmd.error) {
      showErrorSnackBar(context, cmd.result);
      cmd.clearResult();
      _formKey.currentState?.validate();
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    vm.signUp.execute((
      firstName: _first.text,
      lastName: _last.text,
      username: _username.text,
      email: _email.text,
      password: _password.text,
      birthDate: _birth!,
    ));
  }

  static String? _required(String? v, String message) =>
      (v == null || v.trim().isEmpty) ? message : null;

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Create your account',
      subtitle: 'Join your team on Stall 10.',
      child: ListenableBuilder(
        listenable: vm.signUp,
        builder: (context, _) {
          final busy = vm.signUp.running;
          return Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _first,
                          decoration: const InputDecoration(
                            labelText: 'First name',
                          ),
                          autofillHints: const [AutofillHints.givenName],
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          maxLength: 40,
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
                          textInputAction: TextInputAction.next,
                          maxLength: 40,
                          buildCounter: _noCounter,
                          validator: (v) =>
                              _required(v, 'Enter your last name'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  UsernameField(
                    controller: _username,
                    checker: vm.username,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  FormField<DateTime>(
                    validator: (_) => vm.birthDateProblemOn(_birth),
                    builder: (field) => InkWell(
                      onTap: busy
                          ? null
                          : () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _birth ?? DateTime(now.year - 20),
                                firstDate: DateTime(1900),
                                lastDate: now,
                                initialEntryMode: DatePickerEntryMode.input,
                                helpText: 'Date of birth',
                              );
                              if (picked == null) return;
                              setState(() => _birth = picked);
                              field.didChange(picked);
                              field.validate();
                            },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Date of birth',
                          helperText: 'Only you will see it.',
                          errorText: field.errorText,
                          errorMaxLines: 2,
                          suffixIcon: const Icon(Icons.calendar_today_outlined),
                        ),
                        child: Text(
                          _birth == null
                              ? 'Choose'
                              : MaterialLocalizations.of(
                                  context,
                                ).formatMediumDate(_birth!),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        (v == null ||
                            !RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            ).hasMatch(v.trim()))
                        ? 'Enter a valid email'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: _password,
                    label: 'Password',
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.next,
                    validator: (v) => PasswordPolicy.problem(v ?? ''),
                  ),
                  PasswordStrengthMeter(controller: _password),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: _confirm,
                    label: 'Confirm password',
                    autofillHints: const [AutofillHints.newPassword],
                    onFieldSubmitted: (_) => _submit(),
                    validator: (v) =>
                        v == _password.text ? null : "Passwords don't match",
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy ? null : _submit,
                    child: busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create account'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: busy ? null : () => context.go(Routes.signIn),
                    child: const Text('Already have an account? Sign in'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static Widget? _noCounter(
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    required int? maxLength,
  }) => null;
}
