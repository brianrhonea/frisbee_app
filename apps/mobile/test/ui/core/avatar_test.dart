// C4: Avatar, TeamLogo and AvatarStack, and the older names that wrap them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/avatar.dart';
import 'package:frisbee_app/ui/core/ui/layout.dart';
import 'package:frisbee_app/ui/teams/widgets/team_initials.dart';

import '../../ui_harness/harness.dart';

const _people = <AvatarItem>[
  (name: 'Ana Rivera', imageUrl: null),
  (name: 'Ben Cho', imageUrl: null),
  (name: 'Cam Diaz', imageUrl: null),
  (name: 'Dee Evans', imageUrl: null),
  (name: 'Eli Fox', imageUrl: null),
  (name: 'Fay Gray', imageUrl: null),
];

/// Every state: initials, single name, no name, broken image, sizes, team
/// logos of each kind, and stacks.
Widget _gallery() => const Padding(
  padding: EdgeInsets.all(16),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          Avatar(name: 'Ana Rivera', size: 24),
          Avatar(name: 'Ana Rivera'),
          Avatar(name: 'Ben', size: 56),
          Avatar(name: '', size: 40),
          // A photo that fails to load falls back to the initials.
          Avatar(name: 'Cam Diaz', imageUrl: 'https://invalid.test/x.png'),
        ],
      ),
      SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          TeamLogo(name: 'Seattle Sockeye'),
          TeamLogo(name: 'Sunday Pickup', kind: TeamLogoKind.community),
          TeamLogo(name: 'Oregon State', kind: TeamLogoKind.organization),
          TeamLogo(),
          TeamLogo(kind: TeamLogoKind.community),
          TeamLogo(name: 'Big Logo', size: 64),
        ],
      ),
      SizedBox(height: 16),
      AvatarStack(items: [..._people]),
      SizedBox(height: 12),
      AvatarStack(items: [..._people], max: 3, size: 40),
      SizedBox(height: 12),
      AvatarStack(items: [..._people], total: 40),
      SizedBox(height: 12),
      AvatarStack(items: [_one]),
    ],
  ),
);

const _one = (name: 'Ana Rivera', imageUrl: null);

Widget _host(Widget child, {ThemeData? theme, TextDirection? dir}) =>
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Directionality(
        textDirection: dir ?? TextDirection.ltr,
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets('gallery goldens, light and dark', skip: goldenSkip != null, (
    t,
  ) async {
    await expectGoldens(t, _gallery(), 'avatar_gallery', height: 420);
  });

  for (final theme in GoldenTheme.values) {
    testWidgets('gallery meets contrast and labelling guidelines, '
        '${theme.name}', (t) async {
      await pumpInApp(t, _gallery(), theme: theme, height: 420);
      final h = t.ensureSemantics();
      await expectLater(t, meetsGuideline(textContrastGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      h.dispose();
    });
  }

  group('Avatar', () {
    testWidgets('shows initials of the first two words', (t) async {
      await t.pumpWidget(_host(const Avatar(name: 'ana maria rivera')));
      expect(find.text('AM'), findsOneWidget);
    });

    testWidgets('no name and no photo shows a person icon', (t) async {
      await t.pumpWidget(_host(const Avatar(name: '  ')));
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      expect(find.text('?'), findsNothing);
    });

    testWidgets('a photo URL adds an image over the initials; a failed '
        'photo leaves the initials', (t) async {
      await t.pumpWidget(
        _host(const Avatar(name: 'Cam Diaz', imageUrl: 'https://x.test/a.png')),
      );
      expect(find.byType(Image), findsOneWidget);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('CD'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('no URL, no image', (t) async {
      await t.pumpWidget(_host(const Avatar(name: 'Cam Diaz')));
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('is a circle of the given size', (t) async {
      await t.pumpWidget(_host(const Avatar(name: 'A', size: 56)));
      expect(t.getSize(find.byType(Avatar)), const Size(56, 56));
      expect(find.byType(ClipOval), findsOneWidget);
    });

    testWidgets('announces the name as an image; decorative stays silent', (
      t,
    ) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(_host(const Avatar(name: 'Ana Rivera')));
      expect(find.bySemanticsLabel('Ana Rivera'), findsOneWidget);
      await t.pumpWidget(
        _host(const Avatar(name: 'Ana Rivera', decorative: true)),
      );
      expect(find.bySemanticsLabel('Ana Rivera'), findsNothing);
      h.dispose();
    });

    testWidgets('initials do not grow with text scale 2.0', (t) async {
      await expectNoOverflowWithLargeText(
        t,
        const Center(child: Avatar(name: 'Ana Rivera', size: 24)),
      );
      expect(t.getSize(find.byType(Avatar)), const Size(24, 24));
    });
  });

  group('TeamLogo', () {
    testWidgets('team initials in a rounded square in the badge colour', (
      t,
    ) async {
      await t.pumpWidget(_host(const TeamLogo(name: 'Seattle Sockeye')));
      expect(find.text('SS'), findsOneWidget);
      final box = t.widget<Container>(
        find
            .ancestor(of: find.text('SS'), matching: find.byType(Container))
            .first,
      );
      expect((box.decoration! as BoxDecoration).color, AppColors.light.badge);
      expect(find.byType(ClipRRect), findsOneWidget);
    });

    testWidgets('community uses the accent; no name shows a crest icon', (
      t,
    ) async {
      await t.pumpWidget(
        _host(
          const Column(
            children: [
              TeamLogo(name: 'Sunday Pickup', kind: TeamLogoKind.community),
              TeamLogo(),
              TeamLogo(kind: TeamLogoKind.community),
            ],
          ),
        ),
      );
      expect(find.text('SP'), findsOneWidget);
      expect(find.byIcon(Icons.landscape_outlined), findsOneWidget);
      expect(find.byIcon(Icons.diversity_3_outlined), findsOneWidget);
    });

    testWidgets('image URL shows an image over the fallback', (t) async {
      await t.pumpWidget(
        _host(
          const TeamLogo(name: 'Sockeye', imageUrl: 'https://x.test/l.png'),
        ),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('announces the name; decorative stays silent', (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(_host(const TeamLogo(name: 'Sockeye')));
      expect(find.bySemanticsLabel('Sockeye'), findsOneWidget);
      await t.pumpWidget(
        _host(const TeamLogo(name: 'Sockeye', decorative: true)),
      );
      expect(find.bySemanticsLabel('Sockeye'), findsNothing);
      h.dispose();
    });
  });

  group('AvatarStack', () {
    testWidgets('shows up to max faces then +N', (t) async {
      await t.pumpWidget(_host(AvatarStack(items: _people)));
      expect(find.byType(Avatar), findsNWidgets(4));
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('no +N when everyone fits; empty draws nothing', (t) async {
      await t.pumpWidget(_host(AvatarStack(items: _people.take(3).toList())));
      expect(find.byType(Avatar), findsNWidgets(3));
      expect(find.textContaining('+'), findsNothing);
      await t.pumpWidget(_host(const AvatarStack(items: [])));
      expect(find.byType(Avatar), findsNothing);
    });

    testWidgets('total lets +N count people not in the list', (t) async {
      await t.pumpWidget(_host(AvatarStack(items: _people, total: 40)));
      expect(find.text('+36'), findsOneWidget);
    });

    testWidgets('faces overlap', (t) async {
      await t.pumpWidget(_host(AvatarStack(items: _people, max: 3, size: 40)));
      final a = t.getRect(find.byType(Avatar).at(0));
      final b = t.getRect(find.byType(Avatar).at(1));
      expect(b.left - a.left, lessThan(40));
      expect(b.left - a.left, greaterThan(0));
    });

    testWidgets('reads as one image with every name', (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(_host(AvatarStack(items: _people.take(3).toList())));
      expect(
        find.bySemanticsLabel('Ana Rivera, Ben Cho and Cam Diaz'),
        findsOneWidget,
      );
      await t.pumpWidget(_host(AvatarStack(items: _people, max: 2)));
      expect(
        find.bySemanticsLabel('Ana Rivera, Ben Cho and 4 more'),
        findsOneWidget,
      );
      h.dispose();
    });

    testWidgets('mirrors in RTL: the first face is on the right', (t) async {
      await t.pumpWidget(
        _host(
          AvatarStack(items: _people.take(2).toList()),
          dir: TextDirection.rtl,
        ),
      );
      expect(
        t.getCenter(find.byType(Avatar).at(0)).dx,
        greaterThan(t.getCenter(find.byType(Avatar).at(1)).dx),
      );
    });
  });

  group('older names wrap them', () {
    testWidgets('PersonAvatar, TeamBadge, TeamInitials', (t) async {
      await t.pumpWidget(
        _host(
          const Column(
            children: [
              PersonAvatar(name: 'Ana Rivera', radius: 20),
              TeamBadge(name: 'Seattle Sockeye', size: 36),
              TeamBadge(community: true),
              TeamInitials(name: 'Oregon State', kind: TeamKind.organization),
            ],
          ),
        ),
      );
      expect(find.byType(Avatar), findsOneWidget);
      expect(find.byType(TeamLogo), findsNWidgets(3));
      expect(t.getSize(find.byType(Avatar)), const Size(40, 40));
      expect(find.text('AR'), findsOneWidget);
      expect(find.text('SS'), findsOneWidget);
      expect(find.text('OS'), findsOneWidget);
    });
  });
}
