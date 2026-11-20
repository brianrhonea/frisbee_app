import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/discover.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../learn_content.dart';
import '../view_models/learn_viewmodel.dart';

/// Learn to play: the rules of ultimate for beginners, from Discover and
/// Settings ([learnSections]), with reading progress ([LearnViewModel]):
/// a tick on each lesson read and "N of M read". A lesson is read once the
/// end of it has stayed on screen for [learnReadAfter].
class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key, required this.viewModel});

  final LearnViewModel viewModel;

  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  final _keys = [for (final _ in learnSections) GlobalKey()];

  /// A marker at the end of each lesson, to tell when it's been read.
  final _ends = [for (final _ in learnSections) GlobalKey()];
  final _viewport = GlobalKey();

  /// Lessons whose end is on screen, waiting out [learnReadAfter].
  final _timers = <int, Timer>{};

  LearnViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkRead());
  }

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }

  void _jumpTo(int i) {
    final target = _keys[i].currentContext;
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
                for (final (i, s) in learnSections.indexed)
                  SectionCard(
                    key: _keys[i],
                    title: s.title,
                    action: vm.isRead(s.id)
                        ? Icon(
                            Icons.check_circle,
                            size: 20,
                            color: c.accent,
                            semanticLabel: 'Read',
                          )
                        : null,
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
                                child: const Text('Find a community'),
                              ),
                              OutlinedButton(
                                onPressed: () => context.go(Routes.explore()),
                                child: const Text("See what's coming up"),
                              ),
                            ],
                          ),
                        ],
                        SizedBox(key: _ends[i], height: 0),
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
          ),
        ),
      ),
    );
  }
}

/// A numbered row in "On this page", ticked once it's read.
class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.number,
    required this.title,
    required this.read,
    required this.onTap,
  });

  final int number;
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
              child: read
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
