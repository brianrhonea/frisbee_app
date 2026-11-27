import 'package:flutter/material.dart';

import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/hosted_tournament_viewmodel.dart';
import 'hosted_tournament_screen.dart';

/// A division's bracket on its own page (`/tournaments/:id/bracket/:div`),
/// opened from the Results tab's "Open bracket": the whole bracket with
/// room to scroll, its division's chips to switch, and each game's sheet a
/// tap away. Navy while the event is live or on today, like its page.
class HostedBracketScreen extends StatefulWidget {
  const HostedBracketScreen({
    super.key,
    required this.viewModel,
    required this.divisionId,
  });

  final HostedTournamentViewModel viewModel;

  /// The division it opens on.
  final String divisionId;

  @override
  State<HostedBracketScreen> createState() => _HostedBracketScreenState();
}

class _HostedBracketScreenState extends State<HostedBracketScreen> {
  HostedTournamentViewModel get vm => widget.viewModel;
  bool _picked = false;

  @override
  void initState() {
    super.initState();
    vm.addListener(_pick);
    for (final c in vm.commands) {
      c.addListener(_onCommand);
    }
    _pick();
  }

  @override
  void dispose() {
    vm.removeListener(_pick);
    for (final c in vm.commands) {
      c.removeListener(_onCommand);
    }
    super.dispose();
  }

  /// A game's sheet reports, confirms and sets scores from here too:
  /// failures show as on the event page.
  void _onCommand() {
    for (final c in vm.commands) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
    }
  }

  /// Selects the linked division once the divisions are in.
  void _pick() {
    if (_picked || !vm.loaded) return;
    if (!vm.divisions.any((d) => d.id == widget.divisionId)) return;
    _picked = true;
    if (vm.division?.id != widget.divisionId) {
      vm.selectDivision(widget.divisionId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final t = vm.tournament;
        if (!vm.loaded) {
          return Scaffold(appBar: AppBar(), body: const LoadingState());
        }
        if (t == null) {
          return Scaffold(
            appBar: AppBar(),
            body: vm.error != null
                ? ErrorState(error: vm.error)
                : const EmptyState(
                    icon: Icons.emoji_events_outlined,
                    title: 'Tournament not available',
                    message: 'It may have been deleted or not published yet.',
                  ),
          );
        }
        final c = AppColors.of(context);
        final board = onBoard(t, DateTime.now());
        final d = vm.division;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: board ? c.feature : c.background,
            foregroundColor: board ? c.onFeature : c.ink,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bracket'),
                Text(
                  [t.name, ?d?.label].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: board ? c.onFeatureMuted : c.muted,
                  ),
                ),
              ],
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
            children: [
              if (vm.divisions.length > 1)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      for (final x in vm.divisions)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(x.label),
                            selected: x.id == d?.id,
                            onSelected: (_) => vm.selectDivision(x.id),
                          ),
                        ),
                    ],
                  ),
                ),
              if (vm.bracketGames.isEmpty)
                const EmptyState(
                  icon: Icons.account_tree_outlined,
                  title: 'No bracket yet',
                  message:
                      'The bracket shows here once the schedule is out and '
                      'pool play is done.',
                )
              else
                HostedBracket(viewModel: vm),
            ],
          ),
        );
      },
    );
  }
}
