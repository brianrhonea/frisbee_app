import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/brand.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/join_link_viewmodel.dart';

/// Opened by an invite link (`/join/<code>`), from another app or a
/// message: names the team and joins it with one tap.
class JoinLinkScreen extends StatefulWidget {
  const JoinLinkScreen({super.key, required this.viewModel});

  final JoinLinkViewModel viewModel;

  @override
  State<JoinLinkScreen> createState() => _JoinLinkScreenState();
}

class _JoinLinkScreenState extends State<JoinLinkScreen> {
  JoinLinkViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.join.addListener(_onJoin);
  }

  @override
  void dispose() {
    vm.join.removeListener(_onJoin);
    super.dispose();
  }

  void _onJoin() {
    switch (vm.join.result) {
      case Ok(:final value):
        vm.join.clearResult();
        context.go(Routes.team(value));
      case Error():
        showErrorSnackBar(context, vm.join.result);
        vm.join.clearResult();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(leading: backOr(context, Routes.home)),
    body: ListenableBuilder(
      listenable: Listenable.merge([vm, vm.join]),
      builder: (context, _) {
        if (!vm.loaded) return const LoadingView();
        if (vm.error != null) {
          return EmptyView(
            icon: Icons.link_off,
            title: "This invite link doesn't work anymore",
            message:
                'Invite links expire. Ask whoever sent it for a new '
                'one.',
            action: FilledButton(
              onPressed: () => context.go(Routes.home),
              child: const Text('Go home'),
            ),
          );
        }
        final c = AppColors.of(context);
        final name = vm.teamName;
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  const AppLogo(size: 72),
                  const SizedBox(height: 20),
                  Text(
                    vm.alreadyMember
                        ? "You're already on ${name ?? 'this team'}"
                        : "You're invited to join ${name ?? 'a team'}",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    vm.alreadyMember
                        ? 'Open it to see the schedule, chat and roster.'
                        : 'Join as a player to see the schedule, chat and '
                              'roster.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: vm.join.running ? null : vm.join.execute,
                      child: Text(
                        vm.alreadyMember
                            ? 'Open team'
                            : name == null
                            ? 'Join team'
                            : 'Join $name',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go(Routes.home),
                    child: const Text('Not now'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
