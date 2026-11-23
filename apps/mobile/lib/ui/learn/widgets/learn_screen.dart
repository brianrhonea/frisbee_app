import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/discover.dart';
import '../../../domain/models/guides.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../learn_content.dart';
import '../view_models/learn_viewmodel.dart';
import 'guide_screens.dart';

/// Learn to play, from Discover, Settings and Help: the lessons for
/// beginners ([learnSections]), then the rules of ultimate in our words
/// ([rulesGuide], each opening in place) with the official rule books.
/// Reading progress ([LearnViewModel]) covers the lessons: a tick on each
/// one read and "N of M read". A lesson is read once the end of it has
/// stayed on screen for [learnReadAfter]. `/rules` opens it at the rules
/// ([openRules]).
class LearnScreen extends StatefulWidget {
  const LearnScreen({
    super.key,
    required this.viewModel,
    this.openRules = false,
  });

  final LearnViewModel viewModel;

  /// Scrolled to the rules when it opens.
  final bool openRules;

  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  final _keys = [for (final _ in learnSections) GlobalKey()];

  /// A marker at the end of each lesson, to tell when it's been read.
  final _ends = [for (final _ in learnSections) GlobalKey()];
  final _viewport = GlobalKey();
  final _rules = GlobalKey();

  /// Lessons whose end is on screen, waiting out [learnReadAfter].
  final _timers = <int, Timer>{};

  LearnViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rules = _rules.currentContext;
      if (widget.openRules && rules != null) Scrollable.ensureVisible(rules);
      _checkRead();
    });
  }

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }

  void _jumpTo(int i) => _scrollTo(_keys[i]);

  void _scrollTo(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// Whether lesson [i]'s end marker is inside the scroll view's box.
  bool _endShown(int i) {
    final view = _viewport.currentContext?.findRenderObject();
    final end = _ends[i].currentContext?.findRenderObject();
    if (view is! RenderBox || end is! RenderBox) return false;
    if (!view.attached || !end.attached) return false;
    final top = view.localToGlobal(Offset.zero).dy;
    final y = end.localToGlobal(Offset.zero).dy;
    return y >= top && y <= top + view.size.height;
  }

  /// Starts the wait for each unread lesson whose end came into view, and
  /// stops it for those that left.
  void _checkRead() {
    if (!mounted) return;
    for (final (i, s) in learnSections.indexed) {
      if (vm.isRead(s.id) || !_endShown(i)) {
        _timers.remove(i)?.cancel();
        continue;
      }
      _timers[i] ??= Timer(learnReadAfter, () {
        _timers.remove(i);
        if (mounted && _endShown(i)) vm.markRead(s.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Learn to play')),
      body: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _checkRead();
          return false;
        },
        child: ListenableBuilder(
          listenable: vm,
          builder: (context, _) => KeyedSubtree(
            key: _viewport,
            child: PageScroll(
              children: [
                const PageHeader(
                  eyebrow: 'Learn to play',
                  title: 'Ultimate in five minutes',
                  subtitle: learnIntro,
                ),
                // The sections as a numbered list; each row jumps to its
                // part, with a tick once it's read.
                SectionCard(
                  title: 'On this page',
                  action: Text(
                    vm.progressLabel,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: c.muted,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, s) in learnSections.indexed) ...[
                        if (i > 0) Divider(height: 1, color: c.border),
                        _SectionRow(
                          number: i + 1,
                          title: s.title,
                          read: vm.isRead(s.id),
                          onTap: () => _jumpTo(i),
                        ),
                      ],
                      Divider(height: 1, color: c.border),
                      _SectionRow(
                        key: const Key('learn-to-rules'),
                        title: 'The rules of ultimate',
                        onTap: () => _scrollTo(_rules),
                      ),
                      if (vm.readCount > 0)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: c.ink2,
                            ),
                            onPressed: vm.markAllUnread.running
                                ? null
                                : vm.markAllUnread.execute,
                            child: const Text('Mark all unread'),
                          ),
                        ),
                    ],
                  ),
                ),
                // Every lesson in one card, divided, rather than a card each:
                // calmer on a phone.
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, s) in learnSections.indexed) ...[
                        if (i > 0) Divider(height: 1, color: c.border),
                        _Lesson(
                          key: _keys[i],
                          number: i + 1,
                          section: s,
                          read: vm.isRead(s.id),
                          end: _ends[i],
                          last: i == learnSections.length - 1,
                        ),
                      ],
                    ],
                  ),
                ),
                _RulesPart(key: _rules),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
                  child: Text(
                    learnDisclaimer,
                    style: TextStyle(fontSize: 12.5, color: c.muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A numbered row in "On this page", ticked once it's read.
class _SectionRow extends StatelessWidget {
  const _SectionRow({
    super.key,
    this.number,
    required this.title,
    this.read = false,
    required this.onTap,
  });

  /// None: the rules, with a whistle instead.
  final int? number;
  final String title;
  final bool read;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: read ? c.accent : null,
                border: read ? null : Border.all(color: c.border2, width: 1.5),
              ),
              child: number == null
                  ? Icon(Icons.sports, size: 16, color: c.ink2)
                  : read
                  ? Icon(
                      Icons.check,
                      size: 16,
                      color: c.onAccent,
                      semanticLabel: 'Read',
                    )
                  : Text(
                      '$number',
                      style: TextStyle(
                        fontFamily: scoreFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: c.ink2,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: c.muted),
          ],
        ),
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

/// One lesson: its number and title (ticked once read), then its text.
class _Lesson extends StatelessWidget {
  const _Lesson({
    super.key,
    required this.number,
    required this.section,
    required this.read,
    required this.end,
    required this.last,
  });

  final int number;
  final LearnSection section;
  final bool read;

  /// The marker at its end, to tell when it's been read.
  final GlobalKey end;

  /// The last lesson ends with ways to find a game.
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$number',
                style: TextStyle(
                  fontFamily: scoreFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: c.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    letterSpacing: -0.2,
                    color: c.ink,
                  ),
                ),
              ),
              if (read)
                Icon(
                  Icons.check_circle,
                  size: 20,
                  color: c.accent,
                  semanticLabel: 'Read',
                ),
            ],
          ),
          const SizedBox(height: 10),
          for (final b in section.blocks) _Block(block: b),
          if (last) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: () => context.go(Routes.explore()),
                  child: const Text('Find a community'),
                ),
                OutlinedButton(
                  onPressed: () => context.go(Routes.explore()),
                  child: const Text("See what's coming up"),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(key: end, height: 0),
        ],
      ),
    );
  }
}

/// The rules of ultimate ([rulesGuide]), after the lessons: the official
/// rule books, then each rule opening in place.
class _RulesPart extends StatelessWidget {
  const _RulesPart({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'THE RULES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: c.accent,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'The rules of ultimate',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                rulesIntro,
                style: TextStyle(fontSize: 14.5, height: 1.45, color: c.ink2),
              ),
            ],
          ),
        ),
        const SectionCard(
          title: 'Official rules',
          padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: OfficialRuleLinks(),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, s) in rulesGuide.indexed) ...[
                if (i > 0) Divider(height: 1, color: c.border),
                GuideTile(key: Key('rules-${s.id}'), section: s),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text(
            rulesDisclaimer,
            style: TextStyle(fontSize: 12.5, color: c.muted),
          ),
        ),
      ],
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
