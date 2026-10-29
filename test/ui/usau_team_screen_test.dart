import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/usau_team/usau_team_repository.dart';
import 'package:frisbee_app/domain/models/usau_team.dart';
import 'package:frisbee_app/ui/rankings/view_models/usau_team_viewmodel.dart';
import 'package:frisbee_app/ui/rankings/widgets/usau_team_screen.dart';
import 'package:frisbee_app/utils/result.dart';

class _FakeRepo implements UsauTeamRepository {
  _FakeRepo(this.team);

  final UsauTeam team;

  @override
  Future<Result<UsauTeam>> getTeam(String url) async => Result.ok(team);
}

void main() {
  final team = UsauTeam(
    name: 'Alpha',
    url: 'https://play.usaultimate.org/teams/events/Eventteam/?TeamId=abc',
    events: [
      UsauEvent(
        name: 'Pro Championships',
        startDate: DateTime.utc(2026, 8, 2, 12),
        endDate: DateTime.utc(2026, 8, 4, 12),
        placement: '1st',
      ),
      UsauEvent(
        name: 'Fall Classic',
        startDate: DateTime.utc(2026, 11, 7, 12),
        endDate: DateTime.utc(2026, 11, 8, 12),
      ),
    ],
    games: const [
      UsauGame(
        opponent: 'Beta',
        tournament: 'Pro Championships',
        score: '13-9',
      ),
      UsauGame(
        opponent: 'Gamma',
        tournament: 'Pro Championships',
        score: '8-13',
      ),
      UsauGame(opponent: 'Zeta', tournament: 'Fall Classic'),
    ],
  );

  UsauTeamViewModel viewModel() => UsauTeamViewModel(
    url: team.url,
    name: team.name,
    usauTeamRepository: _FakeRepo(team),
    clock: () => DateTime.utc(2026, 10, 28),
  );

  Color? fillOf(WidgetTester tester, String text) => tester
      .widget<ListTile>(
        find.ancestor(of: find.text(text), matching: find.byType(ListTile)),
      )
      .tileColor;

  testWidgets('wins are filled green; losses and upcoming use the theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: UsauTeamScreen(viewModel: viewModel())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Events & Schedule'));
    await tester.pumpAndSettle();

    final green = Colors.green.shade100;
    expect(fillOf(tester, 'vs Beta'), green);
    expect(fillOf(tester, 'vs Gamma'), isNull);
    expect(fillOf(tester, 'vs Zeta'), isNull);

    // Event list: the won past event is green, the upcoming one is not.
    final eventTiles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .where((t) => t.title is Text)
        .toList();
    final pro = eventTiles.firstWhere(
      (t) => (t.title! as Text).data == 'Pro Championships',
    );
    final fall = eventTiles.firstWhere(
      (t) => (t.title! as Text).data == 'Fall Classic',
    );
    expect(pro.tileColor, green);
    expect(fall.tileColor, isNull);
    expect(find.text('Upcoming'), findsWidgets);
  });
}
