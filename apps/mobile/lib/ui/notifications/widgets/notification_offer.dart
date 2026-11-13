import 'package:flutter/material.dart';

import '../../../domain/models/notification.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/brand.dart';
import '../../core/ui/error_message.dart';

/// Asks whether to turn on notifications, in a bottom sheet: [title],
/// [message], then "Turn on" and [declineLabel]. True for Turn on, false
/// for decline, null if the sheet was swiped away.
Future<bool?> showNotificationOffer(
  BuildContext context, {
  required String title,
  required String message,
  String declineLabel = 'Not now',
}) => showModalBottomSheet<bool>(
  context: context,
  showDragHandle: true,
  builder: (context) {
    final c = AppColors.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.notifications_active_outlined, size: 36, color: c.ink),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Turn on'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(declineLabel),
            ),
          ],
        ),
      ),
    );
  },
);

/// Tells the user how asking for push went: a pointer to the system
/// settings when it's turned off there, else [enabled] if given.
void showPushOutcome(
  BuildContext context,
  PushStatus? status, {
  String? enabled,
}) {
  switch (status) {
    case PushStatus.denied:
      showSnackBar(
        context,
        'Notifications are off for $appName. '
        "Turn them on in your phone's Settings.",
      );
    case PushStatus.enabled when enabled != null:
      showSnackBar(context, enabled);
    default:
      break;
  }
}
