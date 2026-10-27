import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/routes.dart';
import '../../core/ui/error_message.dart';
import '../view_models/sign_in_viewmodel.dart';
import 'auth_layout.dart';

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

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    vm.signIn.execute((email: _email.text, password: _password.text));
  }

  void _forgotPassword() {
    if (_email.text.trim().isEmpty) {
      showSnackBar(context, 'Enter your email first.');
      return;
    }
    vm.sendPasswordReset.execute(_email.text);
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Sign in',
      child: ListenableBuilder(
        listenable: Listenable.merge([
          vm.signIn,
          vm.signInWithGoogle,
          vm.signInWithApple,
        ]),
        builder: (context, _) {
          final busy = vm.busy;
          return Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'Enter a valid email'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => _submit(),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Enter your password' : null,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
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
                  if (vm.showGoogle || vm.showApple) ...[
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('or'),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (vm.showGoogle)
                    OutlinedButton.icon(
                      onPressed: busy ? null : vm.signInWithGoogle.execute,
                      icon: const Icon(Icons.g_mobiledata, size: 28),
                      label: const Text('Continue with Google'),
                    ),
                  if (vm.showApple) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: busy ? null : vm.signInWithApple.execute,
                      icon: const Icon(Icons.apple),
                      label: const Text('Continue with Apple'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: busy ? null : () => context.go(Routes.signUp),
                    child: const Text("Don't have an account? Sign up"),
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
