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

/// Above the rules on Learn to play.
const rulesIntro =
    'A plain-language guide to how ultimate is played. For anything it '
    'leaves out, or if a call is in doubt, the official rules decide.';

/// Under the rules on Learn to play.
const rulesDisclaimer =
    "This guide is Stall 10's summary, not an official rule book. Events "
    'can change things like game length and timeouts.';

/// The official rule books ([officialRules]), each opening in the browser.
class OfficialRuleLinks extends StatelessWidget {
  const OfficialRuleLinks({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final l in officialRules)
        ListTile(
          key: Key('official-${l.url}'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.open_in_new, size: 20),
          title: Text(
            l.label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(l.note),
          onTap: () => _open(context, Uri.parse(l.url)),
        ),
    ],
  );
}

/// One rule ([rulesGuide]) or help topic, opening in place to its points.
class GuideTile extends StatelessWidget {
  const GuideTile({super.key, required this.section});

  final GuideSection section;

  @override
  Widget build(BuildContext context) => Theme(
    // No lines above and below an opened section.
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      title: Text(
        section.title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [GuidePoints(section: section)],
    ),
  );
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
                  GuideTile(key: Key('help-${s.id}'), section: s),
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
                  key: const Key('help-learn'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.menu_book_outlined),
                  title: const Text('Learn to play'),
                  subtitle: const Text('The basics and the rules of ultimate'),
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

/// A section's intro and its points as a bulleted list.
class GuidePoints extends StatelessWidget {
  const GuidePoints({super.key, required this.section});

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
                  padding: const EdgeInsets.only(top: AppSpace.sm, right: 10),
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
