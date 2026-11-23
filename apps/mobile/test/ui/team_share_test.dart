// Splitting a team fee on the team's page (TeamShareCard); the website's
// TeamShare and the API's team_share.test.ts check the same.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/team_share/team_share_repository.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_share.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/teams/widgets/team_share_card.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';

class FakeTeamShareRepository implements TeamShareRepository {
  FakeTeamShareRepository(this.current);

  TeamShareView current;
  final saved = <({int amountCents, String note})>[];
  final marks = <({String uid, bool paid})>[];
  bool cleared = false;

  @override
  Future<Result<TeamShareView>> view(String teamId) async => Result.ok(current);

  @override
  Future<Result<TeamShareView>> set(
    String teamId, {
    required int amountCents,
    required String note,
  }) async {
    saved.add((amountCents: amountCents, note: note));
    current = TeamShareView(
      share: TeamShare(
        amountCents: amountCents,
        currency: 'usd',
        note: note,
        collectorId: 'me',
        collectorName: 'Me',
      ),
      manages: true,
      members: const [
        TeamShareMember(uid: 'pat', name: 'Pat', paid: false),
        TeamShareMember(uid: 'sam', name: 'Sam', paid: false),
      ],
    );
    return Result.ok(current);
  }

  @override
  Future<Result<void>> clear(String teamId) async {
    cleared = true;
    return const Result.ok(null);
  }

  @override
  Future<Result<TeamShareView>> markPaid(
    String teamId,
    String uid, {
    required bool paid,
  }) async {
    marks.add((uid: uid, paid: paid));
    current = TeamShareView(
      share: current.share,
      manages: true,
      members: [
        for (final m in current.members)
          TeamShareMember(
            uid: m.uid,
            name: m.name,
            paid: m.uid == uid ? paid : m.paid,
          ),
      ],
    );
    return Result.ok(current);
  }
}

Widget _card(FakeTeamShareRepository repo, Team team) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: Provider<TeamShareRepository?>.value(
      value: repo,
      child: SingleChildScrollView(child: TeamShareCard(team: team)),
    ),
  ),
);

void main() {
  final team = teamWith({
    'me': TeamRole.owner,
    'pat': TeamRole.player,
    'sam': TeamRole.player,
    'cap': TeamRole.player,
  });

  testWidgets('an admin splits the total evenly, then marks people paid', (
    tester,
  ) async {
    final repo = FakeTeamShareRepository(const TeamShareView(manages: true));
    await tester.pumpWidget(_card(repo, team));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share-start')));
    await tester.pumpAndSettle();
    // $160 among the 4 people on the team.
    await tester.enterText(find.byKey(const Key('share-total')), '160');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('share-amount')))
          .controller!
          .text,
      '40.00',
    );
    await tester.enterText(find.byKey(const Key('share-note')), 'Venmo @me');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.saved.single, (amountCents: 4000, note: 'Venmo @me'));
    expect(find.text(r'$40 each, paid to you'), findsOneWidget);
    expect(find.text(r'0 of 2 paid · $0 in, $80 to go'), findsOneWidget);

    await tester.tap(find.byKey(const Key('share-paid-pat')));
    await tester.pumpAndSettle();
    expect(repo.marks.single, (uid: 'pat', paid: true));
    expect(find.text(r'1 of 2 paid · $40 in, $40 to go'), findsOneWidget);
  });

  testWidgets('a member sees their share and how to pay; nothing without one', (
    tester,
  ) async {
    final repo = FakeTeamShareRepository(
      const TeamShareView(
        share: TeamShare(
          amountCents: 4050,
          currency: 'usd',
          note: 'Cash at practice',
          collectorId: 'me',
          collectorName: 'Alex',
        ),
        mine: false,
      ),
    );
    await tester.pumpWidget(_card(repo, team));
    await tester.pumpAndSettle();
    expect(find.text(r'$40.50 each, paid to Alex'), findsOneWidget);
    expect(find.text('Cash at practice'), findsOneWidget);
    expect(find.text('Not paid yet'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);

    repo.current = TeamShareView.none;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_card(repo, team));
    await tester.pumpAndSettle();
    expect(find.text('Split a team fee'), findsNothing);
  });

  test('even shares round up to the cent; totals add up', () {
    expect(evenShare(10000, 3), 3334);
    expect(evenShare(0, 3), 0);
    final t = shareTotals(4000, const [
      TeamShareMember(uid: 'a', name: 'A', paid: true),
      TeamShareMember(uid: 'b', name: 'B', paid: false),
    ]);
    expect(t, (paid: 1, owed: 1, collectedCents: 4000, outstandingCents: 4000));
  });
}
