import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/moderation/moderation_repository.dart';
import '../../../domain/models/moderation.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/user_avatar.dart';
import 'report_sheet.dart';

/// Opens Settings › Blocked accounts.
Future<void> showBlockedAccounts(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const BlockedAccountsScreen()));

/// Everyone the user blocked, with Unblock (the website's
/// /settings/blocked).
class BlockedAccountsScreen extends StatelessWidget {
  const BlockedAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final blocked = context.watch<ModerationRepository>().current.mine;
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked accounts')),
      body: blocked.isEmpty
          ? const EmptyState(
              icon: Icons.block,
              title: 'Nobody blocked',
              message:
                  'Block someone from their profile or your conversation '
                  'with them. $blockExplainer',
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    blockExplainer,
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ),
                for (final b in blocked)
                  ListTile(
                    key: ValueKey('blocked-${b.uid}'),
                    leading: UserAvatar(
                      uid: b.uid,
                      name: b.name,
                      photoUrl: b.photoUrl,
                    ),
                    title: Text(b.name),
                    subtitle: b.username == null
                        ? null
                        : Text('@${b.username}'),
                    trailing: OutlinedButton(
                      onPressed: () =>
                          confirmUnblock(context, uid: b.uid, name: b.name),
                      child: const Text('Unblock'),
                    ),
                  ),
              ],
            ),
    );
  }
}
