import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/usau_attribution.dart';
import '../view_models/tournaments_viewmodel.dart';
import 'tournaments_screen.dart';

class TournamentDetailScreen extends StatelessWidget {
  const TournamentDetailScreen({
    super.key,
    required this.viewModel,
    required this.tournamentId,
  });

  final TournamentsViewModel viewModel;
  final String tournamentId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final t = viewModel.byId(tournamentId);
        if (viewModel.loading) {
          return Scaffold(appBar: AppBar(), body: const LoadingView());
        }
        if (t == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyView(
              icon: Icons.event_busy,
              title: 'Tournament not found',
            ),
          );
        }
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(title: Text(t.name)),
          body: ConstrainedContent(
            maxWidth: 640,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(t.name, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: Text(formatDateRange(t.startDate, t.endDate)),
                ),
                if (t.location.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(t.location),
                  ),
                if (t.competitionLevel.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.military_tech_outlined),
                    title: Text(t.competitionLevel),
                  ),
                if (t.divisions.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.groups_outlined),
                    title: Text(t.divisions.join(', ')),
                  ),
                const SizedBox(height: 16),
                if (t.url.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () async {
                      final ok = await launchUrl(Uri.parse(t.url));
                      if (!ok && context.mounted) {
                        showSnackBar(context, 'Could not open link');
                      }
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('View on USA Ultimate'),
                  ),
                const UsauAttribution(),
              ],
            ),
          ),
        );
      },
    );
  }
}
