import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:frisbee_app/data/repositories/auth/auth_repository.dart';
import 'package:frisbee_app/data/repositories/moderation/moderation_repository.dart';
import 'package:frisbee_app/domain/models/moderation.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/moderation/view_models/team_reports_viewmodel.dart';
import 'package:frisbee_app/ui/moderation/widgets/blocked_accounts_screen.dart';
import 'package:frisbee_app/ui/moderation/widgets/team_reports_screen.dart';
import 'package:frisbee_app/ui/posts/widgets/post_widgets.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';
import '../testing/moderation_fakes.dart';

/// Report and block (the website's Report.tsx, BlockedSettings and
/// TeamReports have the matching behaviour).
void main() {
  group('ReportReason', () {
    test('matches reportReasons and their labels in packages/shared', () {
      final ts = File(
        '../../packages/shared/src/moderation.ts',
      ).readAsStringSync();
      for (final r in ReportReason.values) {
        expect(ts, contains('${r.wire}: "${r.label}"'), reason: r.name);
        expect(ts, contains('"${r.wire}",'), reason: r.name);
      }
      final listed = RegExp(
        r'export const reportReasons = \[([^\]]*)\]',
      ).firstMatch(ts)!.group(1)!;
      expect(
        RegExp(r'"(\w+)"').allMatches(listed).map((m) => m.group(1)).toList(),
        ReportReason.values.map((r) => r.wire).toList(),
      );
    });
  });

  group('ReportTarget', () {
    test('every kind round-trips through JSON', () {
      const targets = <ReportTarget>[
        PostReport('p1'),
        CommentReport('p1', 'c1'),
        TeamPostReport('t1', 'p1'),
        TeamPostCommentReport('t1', 'p1', 'c1'),
        TeamMessageReport('t1', 'r1', 'm1'),
        DirectMessageReport('d1', 'm1'),
        PersonReport('u2'),
      ];
      for (final t in targets) {
        final back = ReportTarget.fromJson(t.toJson())!;
        expect(back.toJson(), t.toJson());
        expect(back.noun, t.noun);
      }
      expect(const TeamMessageReport('t', 'r', 'm').team, isTrue);
      expect(const DirectMessageReport('d', 'm').team, isFalse);
    });

    test('a team report reads its snapshot', () {
      final r = ReportInfo.fromMap({
        'id': 'x',
        'target': {'kind': 'teamPost', 'teamId': 't1', 'postId': 'p1'},
        'reason': 'self_harm',
        'authorId': 'u2',
        'authorName': 'Sam',
        'snapshot': {
          'text': 'hello',
          'images': ['https://a/b.jpg'],
        },
      });
      expect(r.reason, ReportReason.selfHarm);
      expect(r.target, isA<TeamPostReport>());
      expect(r.text, 'hello');
      expect(r.images, hasLength(1));
    });
  });

  UserPost post(String author, {RepostOf? repostOf}) => UserPost(
    id: 'p1',
    authorId: author,
    authorName: author == testUser.uid ? 'Alex' : 'Sam',
    body: 'Hello there',
    createdAt: DateTime(2026, 11, 2, 9),
    repostOf: repostOf,
  );

  Future<void> pump(
    WidgetTester tester,
    Widget child,
    FakeModerationRepository mod,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ],
      errorBuilder: (_, state) => Text('Went to ${state.uri.path}'),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthRepository>.value(
            value: FakeAuthRepository(user: testUser),
          ),
          ChangeNotifierProvider<ModerationRepository>.value(value: mod),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Widget card(UserPost p) =>
      UserPostCard(post: p, loadImage: (_) async => Result.ok(Uint8List(0)));

  testWidgets('reporting a post sends the reason, and can block too', (
    tester,
  ) async {
    final mod = FakeModerationRepository();
    await pump(tester, card(post('u2')), mod);
    await tester.tap(find.byTooltip('Post options'));
    await tester.pumpAndSettle();
    expect(find.text('Block Sam'), findsOneWidget);
    await tester.tap(find.text('Report post'));
    await tester.pumpAndSettle();
    expect(find.text('Report this post'), findsOneWidget);
    // Report waits for a reason.
    final send = find.widgetWithText(FilledButton, 'Report');
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('reason-harassment')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Also block Sam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Also block Sam'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(mod.reports, hasLength(1));
    final r = mod.reports.single;
    expect(r.target.toJson(), {'kind': 'post', 'postId': 'p1'});
    expect(r.reason, ReportReason.harassment);
    expect(r.block, isTrue);
    expect(find.textContaining('you blocked Sam'), findsOneWidget);
    // Blocked: the post is gone.
    expect(find.text('Hello there'), findsNothing);
  });

  testWidgets("someone's own post has no Report", (tester) async {
    await pump(tester, card(post(testUser.uid)), FakeModerationRepository());
    expect(find.byTooltip('Post options'), findsNothing);
  });

  testWidgets('posts and reposts of someone blocked are hidden', (
    tester,
  ) async {
    final mod = FakeModerationRepository(
      blocks: const BlockList(hidden: {'u2'}),
    );
    await pump(
      tester,
      Column(
        children: [
          card(post('u2')),
          card(
            UserPost(
              id: 'p2',
              authorId: 'u3',
              authorName: 'Kim',
              body: 'Look',
              repostOf: const RepostOf(
                postId: 'p1',
                authorId: 'u2',
                authorName: 'Sam',
              ),
            ),
          ),
        ],
      ),
      mod,
    );
    expect(find.text('Hello there'), findsNothing);
    expect(find.text('Look'), findsNothing);
  });

  testWidgets('Block asks first, then hides them', (tester) async {
    final mod = FakeModerationRepository();
    await pump(tester, card(post('u2')), mod);
    await tester.tap(find.byTooltip('Post options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block Sam'));
    await tester.pumpAndSettle();
    expect(find.text('Block Sam?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Block'));
    await tester.pumpAndSettle();
    expect(mod.blocked, ['u2']);
    expect(find.text('Hello there'), findsNothing);
  });

  testWidgets('Blocked accounts lists them and unblocks', (tester) async {
    final mod = FakeModerationRepository(
      blocks: const BlockList(
        mine: [BlockedAccount(uid: 'u2', name: 'Sam', username: 'sam')],
        hidden: {'u2'},
      ),
    );
    await pump(tester, const SizedBox(), mod);
    final context = tester.element(find.byType(SizedBox).first);
    showBlockedAccounts(context);
    await tester.pumpAndSettle();
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('@sam'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Unblock'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Unblock'));
    await tester.pumpAndSettle();
    expect(mod.unblocked, ['u2']);
    expect(find.text('Nobody blocked'), findsOneWidget);
  });

  testWidgets("a team's Reports remove or dismiss", (tester) async {
    final mod = FakeModerationRepository()
      ..teamQueue = [
        ReportInfo.fromMap({
          'id': 'r1',
          'target': {
            'kind': 'teamMessage',
            'teamId': 't1',
            'roomId': 'g',
            'messageId': 'm1',
          },
          'reason': 'spam',
          'authorId': 'u2',
          'authorName': 'Sam',
          'snapshot': {'text': 'Buy followers'},
        }),
        ReportInfo.fromMap({
          'id': 'r2',
          'target': {'kind': 'teamPost', 'teamId': 't1', 'postId': 'p1'},
          'reason': 'other',
          'authorId': 'u3',
          'authorName': 'Kim',
        }),
      ];
    final vm = TeamReportsViewModel(repository: mod, teamId: 't1');
    await pump(tester, const SizedBox(), mod);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TeamReportsScreen(viewModel: vm),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A message by Sam'), findsOneWidget);
    expect(find.text('Buy followers'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Remove').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(mod.resolved, [('r1', true)]);
    expect(find.text('A message by Sam'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Dismiss'));
    await tester.pumpAndSettle();
    expect(mod.resolved.last, ('r2', false));
    expect(find.text('No open reports'), findsOneWidget);
    vm.dispose();
  });
}
