import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../view_models/meeting_alerts_viewmodel.dart';
import '../../../routing/open_link.dart';

/// Shows a snack bar with a Join button when a meeting the user is
/// attending starts. Sits above the router, so it's given the router and the
/// app's [ScaffoldMessenger] key.
class MeetingAlerts extends StatefulWidget {
  const MeetingAlerts({
    super.key,
    required this.viewModel,
    required this.router,
    required this.messengerKey,
    required this.child,
  });

  final MeetingAlertsViewModel viewModel;
  final GoRouter router;
  final GlobalKey<ScaffoldMessengerState> messengerKey;
  final Widget child;

  @override
  State<MeetingAlerts> createState() => _MeetingAlertsState();
}

class _MeetingAlertsState extends State<MeetingAlerts> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onAlert);
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onAlert);
    super.dispose();
  }

  void _onAlert() {
    final vm = widget.viewModel;
    final messenger = widget.messengerKey.currentState;
    if (messenger == null) return;
    final alert = vm.takeAlert();
    if (alert == null) return;
    final route = alert.route;
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 30),
        showCloseIcon: true,
        content: Row(
          children: [
            const Icon(Icons.videocam, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (alert.body.isNotEmpty) Text(alert.body),
                ],
              ),
            ),
          ],
        ),
        action: route == null
            ? null
            : SnackBarAction(
                label: 'Join',
                onPressed: () {
                  vm.opened(alert);
                  widget.router.openLink(route);
                },
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
