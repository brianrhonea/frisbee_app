import 'package:flutter/material.dart';

import 'app_button.dart';

/// A yes/no question in a dialog (C10): a [title], a [message] and two
/// buttons. The confirm button says what happens ("Delete post"), not
/// "OK". With [destructive] the confirm button takes the destructive
/// button style, for deleting or leaving; Cancel is always there.
///
/// Pops `true` to confirm and `false` to cancel. Use [confirmDialog] to
/// show it.
///
/// Website counterpart: `ConfirmDialog` (apps/web).
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.destructive = false,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      AppButton.ghost(
        cancelLabel,
        onPressed: () => Navigator.pop(context, false),
      ),
      if (destructive)
        AppButton.destructive(
          confirmLabel,
          onPressed: () => Navigator.pop(context, true),
        )
      else
        AppButton.primary(
          confirmLabel,
          onPressed: () => Navigator.pop(context, true),
        ),
    ],
  );
}

/// Shows a [ConfirmDialog] and returns whether the user confirmed
/// (dismissing it counts as no).
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: destructive,
    ),
  );
  return ok ?? false;
}
