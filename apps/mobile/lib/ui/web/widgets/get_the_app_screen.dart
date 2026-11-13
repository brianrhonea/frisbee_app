import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/brand.dart';
import 'store_badges.dart';

/// Where the website sends pages it doesn't have yet (team sections,
/// messages, meetings, workouts…): get the app, or go back to searching.
class GetTheAppScreen extends StatelessWidget {
  const GetTheAppScreen({super.key, this.appOnly = true});

  /// True when the visitor followed a link to something only the app has;
  /// false when they asked for the downloads.
  final bool appOnly;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 88),
                const SizedBox(height: 24),
                Text(
                  appOnly ? "That's in the $appName app" : 'Get $appName',
                  textAlign: TextAlign.center,
                  style: text.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  appOnly
                      ? 'The website has search, profiles, team pages and '
                            'events. Chats, playbooks, meetings, stats and the '
                            'rest live in the app.'
                      : 'Team chats, playbooks, schedules, stats and meetings '
                            'for your ultimate team, on your phone.',
                  textAlign: TextAlign.center,
                  style: text.bodyLarge?.copyWith(color: c.muted),
                ),
                const SizedBox(height: 28),
                const StoreBadges(alignment: WrapAlignment.center),
                const SizedBox(height: 28),
                TextButton.icon(
                  onPressed: () => context.go(Routes.explore()),
                  icon: const Icon(Icons.search),
                  label: const Text('Search on the web'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
