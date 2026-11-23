import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/models/guides.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';

/// Where to write when Help doesn't answer it.
const supportEmail = 'support@stall10.app';

Future<void> _open(BuildContext context, Uri uri) async {
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text("Couldn't open $uri")));
  }
}

/// The rules of ultimate in our own words ([rulesGuide]), with links to the
/// official rule books ([officialRules]). From Settings, Help and Learn.
class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Rules of ultimate')),
      body: PageScroll(
        children: [
          const PageHeader(
            eyebrow: 'Rules',
            title: 'The rules of ultimate',
            subtitle:
                'A plain-language guide to how ultimate is played. For '
                'anything it leaves out, or if a call is in doubt, the '
                'official rules decide.',
          ),
          SectionCard(
            title: 'Official rules',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final l in officialRules)
                  ListTile(
                    key: Key('official-${l.url}'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.open_in_new),
                    title: Text(l.label),
                    subtitle: Text(l.note),
                    onTap: () => _open(context, Uri.parse(l.url)),
                  ),
              ],
            ),
          ),
          for (final s in rulesGuide) _GuideCard(section: s),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
            child: Text(
              "This guide is Stall 10's summary, not an official rule book. "
              'Events can change things like game length and timeouts.',
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Help in Settings: common questions about the app ([helpTopics]), each
/// opening in place, then ways to get more help.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: PageScroll(
        children: [
          const PageHeader(
            eyebrow: 'Help',
            title: 'How can we help?',
            subtitle: 'Answers to the things people ask about most.',
          ),
          SectionCard(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
            child: Column(
              children: [
                for (final (i, s) in helpTopics.indexed) ...[
                  if (i > 0) Divider(height: 1, color: c.border),
                  Theme(
                    // No lines above and below an opened topic.
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      key: Key('help-${s.id}'),
                      title: Text(
                        s.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [_Points(section: s)],
                    ),
                  ),
                ],
              ],
            ),
          ),
          SectionCard(
            title: 'More help',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.sports),
                  title: const Text('Rules of ultimate'),
                  subtitle: const Text('How the game is played'),
                  onTap: () => context.push(Routes.rules),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.menu_book_outlined),
                  title: const Text('Learn to play'),
                  subtitle: const Text('Ultimate in five minutes'),
                  onTap: () => context.push(Routes.learn),
                ),
                ListTile(
                  key: const Key('help-contact'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.mail_outline),
                  title: const Text('Contact support'),
                  subtitle: const Text(supportEmail),
                  onTap: () =>
                      _open(context, Uri(scheme: 'mailto', path: supportEmail)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.section});

  final GuideSection section;

  @override
  Widget build(BuildContext context) => SectionCard(
    key: Key('rules-${section.id}'),
    title: section.title,
    child: _Points(section: section),
  );
}

/// A section's intro and its points as a bulleted list.
class _Points extends StatelessWidget {
  const _Points({required this.section});

  final GuideSection section;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final style = TextStyle(fontSize: 14.5, height: 1.45, color: c.ink);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (section.intro case final intro?)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(intro, style: style),
          ),
        for (final p in section.points)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 10),
                  child: Icon(Icons.circle, size: 6, color: c.accent),
                ),
                Expanded(child: Text(p, style: style)),
              ],
            ),
          ),
      ],
    );
  }
}
