import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../learn_content.dart';

/// Learn to play: the rules of ultimate for beginners, from Explore and
/// Settings. Static content ([learnSections]), so it has no view model.
class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key});

  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  final _keys = [for (final _ in learnSections) GlobalKey()];

  void _jumpTo(int i) {
    final target = _keys[i].currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Learn to play')),
      body: PageScroll(
        children: [
          const PageHeader(
            eyebrow: 'Learn to play',
            title: 'Ultimate in five minutes',
            subtitle: learnIntro,
          ),
          SectionCard(
            title: 'On this page',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, s) in learnSections.indexed)
                  ActionChip(label: Text(s.title), onPressed: () => _jumpTo(i)),
              ],
            ),
          ),
          for (final (i, s) in learnSections.indexed)
            SectionCard(
              key: _keys[i],
              title: s.title,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final b in s.blocks) _Block(block: b),
                  if (i == learnSections.length - 1) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed: () => context.go(Routes.explore()),
                          child: const Text('Find a group'),
                        ),
                        OutlinedButton(
                          onPressed: () => context.go(Routes.findEvents),
                          child: const Text("See what's coming up"),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
            child: Text(
              learnDisclaimer,
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.block});

  final LearnBlock block;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final body = TextStyle(fontSize: 14.5, height: 1.45, color: c.ink);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: switch (block) {
        LearnText(:final text) => Text.rich(_rich(text), style: body),
        LearnBullets(:final items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: body.copyWith(color: c.muted)),
                    Expanded(child: Text.rich(_rich(item), style: body)),
                  ],
                ),
              ),
          ],
        ),
        LearnGlossary(:final terms) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (term, meaning) in terms)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      term,
                      style: body.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(meaning, style: body.copyWith(color: c.muted)),
                  ],
                ),
              ),
          ],
        ),
      },
    );
  }
}

/// [text] with its `**bold**` parts in bold.
TextSpan _rich(String text) {
  final parts = text.split('**');
  return TextSpan(
    children: [
      for (final (i, p) in parts.indexed)
        TextSpan(
          text: p,
          style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w700) : null,
        ),
    ],
  );
}
