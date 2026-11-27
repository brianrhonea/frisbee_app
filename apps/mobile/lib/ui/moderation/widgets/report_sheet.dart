import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/moderation/moderation_repository.dart';
import '../../../domain/models/moderation.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../view_models/report_viewmodel.dart';

/// The signed-in user's blocks, rebuilding on changes; empty without the
/// repository (tests that don't provide one).
BlockList watchBlocks(BuildContext context) {
  try {
    return context.watch<ModerationRepository>().current;
  } on ProviderNotFoundException {
    return BlockList.empty;
  }
}

/// Whether Report and Block belong on something by [authorId]: signed in,
/// someone else's, and reporting is set up.
bool canReport(BuildContext context, String? authorId) {
  if (authorId == null || authorId.isEmpty) return false;
  try {
    final me = context.read<AuthRepository>().currentUser?.uid;
    context.read<ModerationRepository>();
    return me != null && me != authorId;
  } on ProviderNotFoundException {
    return false;
  }
}

/// Opens the Report sheet for [target] by [authorName] ([authorId] is
/// hidden at once when they're blocked too).
Future<void> showReportSheet(
  BuildContext context, {
  required ReportTarget target,
  required String authorName,
  String? authorId,
}) async {
  final repo = context.read<ModerationRepository>();
  final name = authorName.isEmpty ? 'this player' : authorName;
  final vm = ReportViewModel(
    repository: repo,
    target: target,
    authorId: authorId,
  );
  final blocked = await showModalBottomSheet<bool>(
    context: context,
    sheetAnimationStyle: AppMotion.sheetStyle(context),
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => ReportSheet(viewModel: vm, authorName: name),
  );
  vm.dispose();
  if (blocked == null || !context.mounted) return;
  showSnackBar(
    context,
    blocked
        ? "Thanks. We'll review it, and you blocked $name."
        : "Thanks. We'll review it. $name isn't told who reported.",
  );
}

/// Asks, then blocks [uid]. True once blocked.
Future<bool> confirmBlock(
  BuildContext context, {
  required String uid,
  required String name,
}) async {
  final repo = context.read<ModerationRepository>();
  final ok = await confirmDialog(
    context,
    title: 'Block $name?',
    message: blockExplainer,
    confirmLabel: 'Block',
    destructive: true,
  );
  if (!ok || !context.mounted) return false;
  final r = await repo.block(uid, name: name);
  if (!context.mounted) return false;
  if (r case Error(:final error)) {
    showErrorSnackBar(context, error);
    return false;
  }
  showSnackBar(context, 'You blocked $name.');
  return true;
}

/// Asks, then unblocks [uid].
Future<void> confirmUnblock(
  BuildContext context, {
  required String uid,
  required String name,
}) async {
  final repo = context.read<ModerationRepository>();
  final ok = await confirmDialog(
    context,
    title: 'Unblock $name?',
    message:
        "You'll see each other's posts again, and can follow and message "
        'each other.',
    confirmLabel: 'Unblock',
  );
  if (!ok || !context.mounted) return;
  final r = await repo.unblock(uid);
  if (r case Error(:final error) when context.mounted) {
    showErrorSnackBar(context, error);
  }
}

/// Report a post, comment, message or person (App Store guideline 1.2;
/// the website's ReportDialog). Pops true when the author was blocked
/// too, false when only reported.
class ReportSheet extends StatelessWidget {
  const ReportSheet({
    super.key,
    required this.viewModel,
    required this.authorName,
  });

  final ReportViewModel viewModel;
  final String authorName;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final vm = viewModel;
        final failed = vm.send.result;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Report this ${vm.target.noun}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  vm.target.team
                      ? "Stall 10's team and the team's admins review it. "
                            "$authorName isn't told who reported."
                      : "Stall 10's team reviews it. $authorName isn't told "
                            'who reported.',
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
                const SizedBox(height: 8),
                RadioGroup<ReportReason>(
                  groupValue: vm.reason,
                  onChanged: (r) {
                    if (r != null) vm.pick(r);
                  },
                  child: Column(
                    children: [
                      for (final r in ReportReason.values)
                        RadioListTile<ReportReason>(
                          key: ValueKey('reason-${r.name}'),
                          value: r,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(r.label),
                        ),
                    ],
                  ),
                ),
                TextField(
                  maxLength: reportDetailsMax,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(
                    labelText: 'More details (optional)',
                  ),
                  onChanged: (v) => vm.details = v,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: vm.alsoBlock,
                  onChanged: vm.setBlock,
                  title: Text('Also block $authorName'),
                ),
                if (failed case Error(:final error)) ...[
                  Text(
                    errorMessage(error),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  'If someone is in danger, call 911 or your local emergency '
                  'number first.',
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: vm.canSend
                      ? () async {
                          await vm.send.execute();
                          final r = vm.send.result;
                          if (r case Ok(:final value) when context.mounted) {
                            Navigator.pop(context, value);
                          }
                        }
                      : null,
                  child: vm.send.running
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Report'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
