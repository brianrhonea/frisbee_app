import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/moderation.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/view_model_host.dart';
import '../view_models/team_reports_viewmodel.dart';

/// Opens [teamId]'s Reports over its settings.
Future<void> showTeamReports(BuildContext context, String teamId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ViewModelHost(
          create: (c) =>
              TeamReportsViewModel(repository: c.read(), teamId: teamId),
          builder: (_, vm) => TeamReportsScreen(viewModel: vm),
        ),
      ),
    );

/// What members reported in the team's chat, posts and comments (the
/// website's TeamReports). Reporters stay anonymous; Stall 10's staff see
/// these too.
class TeamReportsScreen extends StatefulWidget {
  const TeamReportsScreen({super.key, required this.viewModel});

  final TeamReportsViewModel viewModel;

  @override
  State<TeamReportsScreen> createState() => _TeamReportsScreenState();
}

class _TeamReportsScreenState extends State<TeamReportsScreen> {
  TeamReportsViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.resolve.addListener(_onResolve);
  }

  @override
  void dispose() {
    vm.resolve.removeListener(_onResolve);
    super.dispose();
  }

  void _onResolve() {
    if (vm.resolve.result case Error(:final error)) {
      vm.resolve.clearResult();
      showErrorSnackBar(context, error);
    }
  }

  Future<void> _remove(ReportInfo r) async {
    final ok = await confirmDialog(
      context,
      title: 'Remove it?',
      message: "It's deleted for everyone, and every report on it closes.",
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (ok) vm.resolve.execute((r.id, true));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reports')),
    body: ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        if (!vm.loaded) return const LoadingView();
        if (vm.load.result case Error(:final error) when vm.reports.isEmpty) {
          return ErrorView(error: error);
        }
        if (vm.reports.isEmpty) {
          return const EmptyView(
            icon: Icons.verified_user_outlined,
            title: 'No open reports',
            message:
                "When members report something in the team's chat or "
                "posts, it shows here. They aren't named.",
          );
        }
        return RefreshIndicator(
          onRefresh: vm.load.execute,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              for (final r in vm.reports)
                _ReportCard(
                  report: r,
                  busy: vm.resolve.running,
                  onRemove: () => _remove(r),
                  onDismiss: () => vm.resolve.execute((r.id, false)),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.busy,
    required this.onRemove,
    required this.onDismiss,
  });

  final ReportInfo report;
  final bool busy;
  final VoidCallback onRemove;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final r = report;
    final what = r.target?.noun ?? 'post';
    final by = r.authorName.isEmpty ? 'a member' : r.authorName;
    final when = r.createdAt == null
        ? ''
        : ' · ${DateFormat.MMMd().add_jm().format(r.createdAt!)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A $what by $by',
              style: TextStyle(fontWeight: FontWeight.w700, color: c.ink),
            ),
            Text(
              '${r.reason.label}$when',
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
            if (r.details case final d? when d.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('“$d”', style: TextStyle(color: c.ink)),
            ],
            if (r.text.isNotEmpty || r.images.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: c.muted, width: 3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r.text.isNotEmpty) Text(r.text),
                    if (r.images.isNotEmpty)
                      Text(
                        r.images.length == 1
                            ? '1 photo'
                            : '${r.images.length} photos',
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                  ],
                ),
              ),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: busy ? null : onDismiss,
                  child: const Text('Dismiss'),
                ),
                TextButton(
                  onPressed: busy ? null : onRemove,
                  child: const Text('Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
