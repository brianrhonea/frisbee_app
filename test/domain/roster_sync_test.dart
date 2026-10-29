import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/roster_sync.dart';
import 'package:frisbee_app/domain/models/usau_team.dart';

void main() {
  test('normalizeName drops case, punctuation and extra spaces', () {
    expect(normalizeName("  Jo  O'Neil-Smith, Jr. "), 'jo oneilsmith jr');
  });

  group('RosterSyncPlan', () {
    const roster = [
      RosterPlayer(id: 'a', name: 'Jordan Lee', number: 4, paid: true),
      RosterPlayer(id: 'b', name: 'Sam Q. Rivera'),
      RosterPlayer(id: 'c', name: 'Casey Not Signed'),
      RosterPlayer(id: 'd', name: 'Gone Already', onUsau: false),
    ];
    const usau = [
      UsauPlayer(name: 'JORDAN LEE', number: '7', position: 'Handler'),
      UsauPlayer(name: 'Sam Rivera', number: '0', position: 'Cutter'),
      UsauPlayer(name: 'New Person', number: '0'),
    ];
    final plan = RosterSyncPlan.build(roster, usau);

    test('matches by name, ignoring case and middle names', () {
      expect(plan.matched.map((m) => m.before.id), ['a', 'b']);
      final jordan = plan.matched.first.after;
      expect(jordan.number, 7);
      expect(jordan.position, PlayerPosition.handler);
      expect(jordan.onUsau, isTrue);
      expect(jordan.paid, isTrue, reason: 'Paid is kept');
    });

    test('treats a shared 0 as no number and keeps the existing one', () {
      final sam = plan.matched[1].after;
      expect(sam.number, isNull);
      expect(sam.position, PlayerPosition.cutter);
    });

    test('adds new USAU players and flags missing app players', () {
      expect(plan.added.single.name, 'New Person');
      expect(plan.added.single.id, isEmpty);
      expect(plan.added.single.onUsau, isTrue);
      expect(plan.missing.map((p) => p.id), ['c', 'd']);
      expect(plan.missing.every((p) => p.onUsau == false), isTrue);
    });

    test('writes only what changes', () {
      expect(plan.writes.map((p) => p.id), ['', 'a', 'b', 'c']);
      final again = RosterSyncPlan.build([
        ...plan.matched.map((m) => m.after),
        ...plan.missing,
        plan.added.single.copyWithId('e'),
      ], usau);
      expect(again.writes, isEmpty);
    });

    test('a lone 0 is a real number', () {
      final p = RosterSyncPlan.build(const [], const [
        UsauPlayer(name: 'Zero', number: '0'),
      ]);
      expect(p.added.single.number, 0);
    });
  });
}

extension on RosterPlayer {
  RosterPlayer copyWithId(String id) => RosterPlayer(
    id: id,
    name: name,
    number: number,
    position: position,
    onUsau: onUsau,
    paid: paid,
  );
}
