import 'package:flutter/material.dart';

import '../../../utils/pending_removals.dart';

/// "Post deleted · Undo": shown right after a delete, in place of asking
/// first. Pair it with [PendingRemovals], which waits the same time.
void showUndoSnackBar(
  BuildContext context, {
  required String message,
  required VoidCallback onUndo,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: PendingRemovals.undoWindow,
        persist: false,
        action: SnackBarAction(label: 'Undo', onPressed: onUndo),
      ),
    );
}
