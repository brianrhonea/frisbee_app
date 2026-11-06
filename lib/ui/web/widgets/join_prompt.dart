import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/brand.dart';

/// Where signing in from here should come back to.
String _here(BuildContext context) =>
    GoRouter.of(context).routerDelegate.currentConfiguration.uri.toString();

/// Sign-in, coming back to the current page afterwards.
String signInHere(BuildContext context) => Uri(
  path: Routes.signIn,
  queryParameters: {'from': _here(context)},
).toString();

/// Sign-up, coming back to the current page afterwards.
String signUpHere(BuildContext context) => Uri(
  path: Routes.signUp,
  queryParameters: {'from': _here(context)},
).toString();

/// What a signed-out visitor tried to do, in the prompt's words.
enum LockedAction {
  like('Like a post to share the love.'),
  repost('Repost to share it with your followers.'),
  comment('Join the conversation.'),
  follow('Follow players and teams to see their posts first.'),
  join('Join a team to get its schedule, chats and playbook.'),
  message('Message players and teams.');

  const LockedAction(this.title);

  final String title;
}

/// Asks a signed-out visitor to log in or sign up for [action], like x.com
/// does for likes and follows. Comes back to this page afterwards.
Future<void> showJoinPrompt(BuildContext context, LockedAction action) {
  final signIn = signInHere(context);
  final signUp = signUpHere(context);
  return showDialog<void>(
    context: context,
    builder: (dialog) {
      final c = AppColors.of(dialog);
      final text = Theme.of(dialog).textTheme;
      void go(String location) {
        Navigator.of(dialog).pop();
        context.go(location);
      }

      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: AppLogo(size: 48)),
                const SizedBox(height: 18),
                Text(
                  action.title,
                  textAlign: TextAlign.center,
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Join $appName to keep up with your teams and the '
                  'ultimate community.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: c.muted),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: () => go(signUp),
                  child: const Text('Create account'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => go(signIn),
                  child: const Text('Log in'),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.of(dialog).pop(),
                  child: const Text('Not now'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
