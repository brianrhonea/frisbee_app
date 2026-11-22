import 'package:flutter/material.dart';

import '../../../domain/models/stats.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';

/// A saved line: O/D tag, name and players. Tap to edit.
class LineTile extends StatelessWidget {
  const LineTile({
    super.key,
    required this.line,
    required this.nameOf,
    this.onTap,
    this.onDelete,
  });

  final StatLine line;
  final String Function(String id) nameOf;

  /// Null for viewers who can't edit lines.
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: line.side == Side.offense
            ? AppColors.of(context).accentSoft
            : AppColors.of(context).field,
        foregroundColor: line.side == Side.offense
            ? AppColors.of(context).accentInk
            : AppColors.of(context).ink2,
        child: Text(
          line.side?.short ?? 'O/D',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      title: Text(line.name),
      subtitle: Text([for (final id in line.players) nameOf(id)].join(', ')),
      onTap: onTap,
      trailing: onDelete == null
          ? null
          : IconButton(
              tooltip: 'Delete line',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirmDialog(
                  context,
                  title: 'Delete ${line.name}?',
                  message: 'Points already played keep their stats.',
                  confirmLabel: 'Delete',
                  destructive: true,
                )) {
                  onDelete!();
                }
              },
            ),
    ),
  );
}
