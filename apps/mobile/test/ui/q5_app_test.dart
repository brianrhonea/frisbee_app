// Sprint 5, Q5 (app half): the Posts tile on the athlete profile, the
// default cover, and copy parity with the website. ("Joined" and the other
// copy changes are asserted in the existing Discover, community, chat and
// post-page tests.)
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/player_profile.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/avatar.dart';
import 'package:frisbee_app/ui/core/ui/cover_header.dart';
import 'package:frisbee_app/ui/core/ui/summary_tiles.dart';
import 'package:frisbee_app/ui/profile/view_models/player_profile_viewmodel.dart';
import 'package:frisbee_app/ui/profile/widgets/profile_screen.dart';

import '../testing/fakes.dart';
import '../testing/social_fakes.dart';
import '../ui_harness/harness.dart';

class _FailingPosts extends FakeUserPostRepository {
  @override
  Stream<List<UserPost>> watchPostsByAuthors(
    List<String> authorIds, {
    int limit = 50,
    Set<String> includePrivate = const {},
  }) => Stream.error(Exception('permission-denied'));
}

class _Gated extends FakeUserPostRepository {
  final _gate = Completer<void>();
  void release() => _gate.complete();

  @override
  Stream<List<UserPost>> watchPostsByAuthors(
    List<String> authorIds, {
    int limit = 50,
    Set<String> includePrivate = const {},
  }) async* {
    await _gate.future;
    yield const [];
  }
}

void main() {
  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;
  late FakeUserPostRepository posts;
  final tileLabel = RegExp(r'^\d+\+?, Posts?$');

  setUp(() {
    auth = FakeAuthRepository(user: testUser);
    profiles = FakeProfileRepository()
      ..put(const PlayerProfile(uid: 'p2', name: 'Pat Lee'))
      ..put(const PlayerProfile(uid: 'p3', name: 'Lock Ed', locked: true));
    posts = FakeUserPostRepository();
  });

  void addPosts(String author, int n, {bool private = false}) {
    for (var i = 0; i < n; i++) {
      posts.posts.add(
        UserPost(
          id: '$author-$private-$i',
          authorId: author,
          authorName: author,
          body: 'Post $i',
          isPrivate: private,
          createdAt: DateTime(2026, 11, 1).add(Duration(minutes: i)),
        ),
      );
    }
  }

  PlayerProfileViewModel profileOf(String uid, [FakeUserPostRepository? p]) {
    final vm = PlayerProfileViewModel(
      uid: uid,
      profileRepository: profiles,
      authRepository: auth,
      teamRepository: FakeTeamRepository(),
      statsRepository: FakeStatsRepository(),
      directMessageRepository: FakeDirectMessageRepository(),
      followRepository: FakeFollowRepository(),
      userPostRepository: p ?? posts,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  Future<void> show(WidgetTester t, PlayerProfileViewModel vm) async {
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlayerProfileScreen(viewModel: vm),
      ),
    );
    await t.pumpAndSettle();
  }

  group('Posts tile', () {
    for (final (n, label, caption) in [
      (0, '0', 'Posts'),
      (1, '1', 'Post'),
      (49, '49', 'Posts'),
      (50, '50+', 'Posts'),
      (60, '50+', 'Posts'),
    ]) {
      testWidgets('$n posts reads "$label, $caption"', (t) async {
        final h = t.ensureSemantics();
        addPosts('p2', n);
        await show(t, profileOf('p2'));
        expect(find.bySemanticsLabel('$label, $caption'), findsOneWidget);
        h.dispose();
      });
    }

    testWidgets("someone else's private posts are not counted", (t) async {
      addPosts('p2', 2);
      addPosts('p2', 5, private: true);
      final vm = profileOf('p2');
      await show(t, vm);
      expect(vm.postCountLabel, '2');
    });

    testWidgets('your own profile counts your private posts too', (t) async {
      addPosts(testUser.uid, 2);
      addPosts(testUser.uid, 3, private: true);
      final vm = profileOf(testUser.uid);
      await show(t, vm);
      expect(vm.postCountLabel, '5');
    });

    testWidgets('hidden while loading', (t) async {
      final gated = _Gated();
      final vm = profileOf('p2', gated);
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlayerProfileScreen(viewModel: vm),
        ),
      );
      await t.pump();
      expect(vm.postCountLabel, isNull);
      gated.release();
      await t.pumpAndSettle();
      expect(vm.postCountLabel, '0');
    });

    testWidgets('hidden when the posts fail to load', (t) async {
      final h = t.ensureSemantics();
      final vm = profileOf('p2', _FailingPosts());
      await show(t, vm);
      expect(vm.postCountLabel, isNull);
      expect(find.byType(SummaryTiles), findsOneWidget);
      expect(find.bySemanticsLabel(tileLabel), findsNothing);
      h.dispose();
    });

    testWidgets('hidden on a locked profile', (t) async {
      final h = t.ensureSemantics();
      addPosts('p3', 4);
      final vm = profileOf('p3');
      await show(t, vm);
      expect(vm.locked, isTrue);
      expect(vm.postCountLabel, isNull);
      expect(find.bySemanticsLabel(tileLabel), findsNothing);
      h.dispose();
    });
  });

  group('default cover', () {
    Widget header({String? url}) => SingleChildScrollView(
      child: CoverHeader(
        title: 'Ana Rivera',
        coverUrl: url,
        watermark: 'AR',
        avatar: const Avatar(name: 'Ana Rivera', size: 72),
      ),
    );

    testWidgets('without a photo it draws the watermark, unread', (t) async {
      final h = t.ensureSemantics();
      await pumpInApp(t, header());
      expect(find.byType(DefaultCoverBand), findsOneWidget);
      final mark = find.descendant(
        of: find.byType(DefaultCoverBand),
        matching: find.text('AR'),
      );
      expect(mark, findsOneWidget);
      // The watermark sits under an ExcludeSemantics, and is not read.
      expect(
        find.ancestor(of: mark, matching: find.byType(ExcludeSemantics)),
        findsWidgets,
      );
      expect(find.bySemanticsLabel('AR'), findsNothing);
      h.dispose();
    });

    testWidgets('with a photo that fails, the band stands in', (t) async {
      await pumpInApp(t, header(url: 'https://invalid.test/c.png'));
      expect(t.takeException(), isNull);
      expect(find.text('Ana Rivera'), findsOneWidget);
    });

    testWidgets('keeps at most two letters and is opt-in', (t) async {
      await pumpInApp(
        t,
        const CoverHeader(
          title: 'T',
          watermark: 'ABC',
          avatar: SizedBox(width: 72, height: 72),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(DefaultCoverBand),
          matching: find.text('AB'),
        ),
        findsOneWidget,
      );
      await pumpInApp(
        t,
        const CoverHeader(title: 'T', avatar: SizedBox(width: 72, height: 72)),
      );
      expect(find.byType(DefaultCoverBand), findsNothing);
    });

    testWidgets('the profile uses it without a header photo', (t) async {
      await show(t, profileOf('p2'));
      expect(find.byType(DefaultCoverBand), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DefaultCoverBand),
          matching: find.text('PL'),
        ),
        findsOneWidget,
      );
    });

    for (final theme in GoldenTheme.values) {
      testWidgets('meets accessibility guidelines, ${theme.name}', (t) async {
        await pumpInApp(t, header(), theme: theme);
        await expectAccessible(t);
      });
    }

    testWidgets('fits at text scale 2.0', (t) async {
      await expectNoOverflowWithLargeText(t, header());
      await expectNoOverflowWithLargeText(t, header(), theme: GoldenTheme.dark);
    });

    testWidgets(
      'profile header goldens, light and dark',
      skip: goldenSkip != null,
      (t) async {
        await expectGoldens(t, header(), 'profile_cover_default', height: 260);
      },
    );
  });

  testWidgets('a missing profile says "Player not found"', (t) async {
    await show(t, profileOf('nobody'));
    expect(find.text('Player not found'), findsOneWidget);
  });
}
