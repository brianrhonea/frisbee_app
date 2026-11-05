import 'package:flutter/material.dart';

import '../../../domain/models/notification.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../core/ui/error_message.dart';
import '../../notifications/widgets/notification_offer.dart';
import '../view_models/shell_viewmodel.dart';

/// Shows the shell's notification offers, one at a time: push after
/// sign-in ([ShellViewModel.offerPush]), then each team or group the user
/// joins ([ShellViewModel.joinedTeam]).
class NotificationOffers extends StatefulWidget {
  const NotificationOffers({
    super.key,
    required this.viewModel,
    required this.child,
  });

  final ShellViewModel viewModel;
  final Widget child;

  @override
  State<NotificationOffers> createState() => _NotificationOffersState();
}

class _NotificationOffersState extends State<NotificationOffers> {
  ShellViewModel get vm => widget.viewModel;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    vm.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    vm.removeListener(_check);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _check() {
    if (_asking || !mounted) return;
    if (vm.offerPush) {
      _ask(
        title: 'Turn on notifications?',
        message:
            'Hear about new messages, schedule changes and game-day '
            'reminders. You choose what you get in Notification settings.',
        command: vm.answerPushOffer,
        // Swiping it away counts as "Not now".
        answer: (yes) => vm.answerPushOffer.execute(yes ?? false),
        enabled: "Notifications are on. You'll hear about what matters.",
      );
    } else if (vm.joinedTeam case final team?) {
      _ask(
        title: 'Get notifications from ${team.name}?',
        message:
            'Chat, event changes and reminders. You can change this any time '
            'in Notification settings.',
        declineLabel: 'No thanks',
        command: vm.answerTeamOffer,
        // Swiping it away leaves the team as it is.
        answer: vm.answerTeamOffer.execute,
        enabled: "You'll get notifications from ${team.name}.",
      );
    }
  }

  Future<void> _ask({
    required String title,
    required String message,
    required Command<PushStatus?> command,
    required Future<void> Function(bool? yes) answer,
    String declineLabel = 'Not now',
    String? enabled,
  }) async {
    _asking = true;
    // Let the page that triggered it (e.g. a join) settle first.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final yes = await showNotificationOffer(
      context,
      title: title,
      message: message,
      declineLabel: declineLabel,
    );
    if (!mounted) return;
    await answer(yes);
    if (!mounted) return;
    switch (command.result) {
      case Ok(:final value):
        showPushOutcome(context, value, enabled: enabled);
      case Error(:final error):
        showErrorSnackBar(context, error);
      case null:
        break;
    }
    _asking = false;
    _check();
  }
}
