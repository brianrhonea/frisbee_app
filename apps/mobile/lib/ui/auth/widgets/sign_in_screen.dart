import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/username.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../view_models/sign_in_viewmodel.dart';
import 'auth_layout.dart';
import 'password_field.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.viewModel});

  final SignInViewModel viewModel;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  SignInViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.signIn.addListener(_onResult);
    vm.signInWithGoogle.addListener(_onResult);
    vm.signInWithApple.addListener(_onResult);
    vm.sendPasswordReset.addListener(_onReset);
    // E.g. "Account deleted successfully", once the page is up.
    if (vm.takeNotice() case final notice?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showSnackBar(context, notice);
      });
    }
  }

  @override
  void dispose() {
    vm.signIn.removeListener(_onResult);
    vm.signInWithGoogle.removeListener(_onResult);
    vm.signInWithApple.removeListener(_onResult);
    vm.sendPasswordReset.removeListener(_onReset);
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  // Success navigates via the router's auth redirect; only errors need UI.
  void _onResult() {
    final error = vm.lastError;
    if (error != null) {
      showErrorSnackBar(context, error);
      vm.signIn.clearResult();
      vm.signInWithGoogle.clearResult();
      vm.signInWithApple.clearResult();
    }
  }

  void _onReset() {
    final cmd = vm.sendPasswordReset;
    if (cmd.completed) {
      showSnackBar(context, 'Password reset email sent.');
      cmd.clearResult();
    } else if (cmd.error) {
      showErrorSnackBar(context, cmd.result);
      cmd.clearResult();
    }
  }

  /// Google and Apple: full width, 48 high.
  static final _social = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
  );

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    vm.signIn.execute((email: _email.text, password: _password.text));
  }

  void _forgotPassword() {
    if (!isEmail(_email.text)) {
      showSnackBar(context, 'Enter your email to reset your password.');
      return;
    }
    vm.sendPasswordReset.execute(_email.text);
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Sign in',
      subtitle: 'Good to see you again.',
      child: ListenableBuilder(
        listenable: Listenable.merge([
          vm.signIn,
          vm.signInWithGoogle,
          vm.signInWithApple,
        ]),
        builder: (context, _) {
          final busy = vm.busy;
          final c = AppColors.of(context);
          return Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (vm.showGoogle)
                    OutlinedButton.icon(
                      style: _social,
                      onPressed: busy ? null : vm.signInWithGoogle.execute,
                      icon: const Icon(Icons.g_mobiledata, size: 28),
                      label: const Text('Continue with Google'),
                    ),
                  if (vm.showApple) ...[
                    if (vm.showGoogle) const SizedBox(height: 10),
                    FilledButton.icon(
                      style: _social.copyWith(
                        backgroundColor: WidgetStatePropertyAll(c.ink),
                        foregroundColor: WidgetStatePropertyAll(c.background),
                      ),
                      onPressed: busy ? null : vm.signInWithApple.execute,
                      icon: const Icon(Icons.apple),
                      label: const Text('Continue with Apple'),
                    ),
                  ],
                  if (vm.showGoogle || vm.showApple) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or',
                            style: TextStyle(fontSize: 13, color: c.muted),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(
                      labelText: 'Email or username',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    autofillHints: const [
                      AutofillHints.username,
                      AutofillHints.email,
                    ],
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v == null || v.trim().length < 3)
                        ? 'Enter your email or username'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: _password,
                    label: 'Password',
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => _submit(),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Enter your password' : null,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      style: TextButton.styleFrom(foregroundColor: c.accent),
                      onPressed: busy ? null : _forgotPassword,
                      child: const Text('Forgot password?'),
                    ),
                  ),
                  FilledButton(
                    onPressed: busy ? null : _submit,
                    child: vm.signIn.running
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign in'),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: busy ? null : () => context.go(Routes.signUp),
                    child: Text.rich(
                      TextSpan(
                        text: "Don't have an account? ",
                        style: TextStyle(
                          color: c.muted,
                          fontWeight: FontWeight.w400,
                        ),
                        children: [
                          TextSpan(
                            text: 'Sign up',
                            style: TextStyle(
                              color: c.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
