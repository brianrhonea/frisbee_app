import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/ui/schedule/view_models/event_detail_viewmodel.dart';
import 'package:frisbee_app/ui/schedule/view_models/event_editor_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/team_detail_viewmodel.dart';

import '../testing/fakes.dart';

void main() {
  late FakeTeamRepository teams;
  late FakeEventRepository events;
  final auth = FakeAuthRepository(user: testUser);

  const poll = EventPoll(
    question: 'Jerseys?',
    options: [
      PollOption(id: 'a', text: 'Dark'),
      PollOption(id: 'b', text: 'Light'),
    ],
  );

  setUp(() {
    teams = FakeTeamRepository();
    events = FakeEventRepository();
    teams.teams['t1'] = teamWith({
      'owner': TeamRole.owner,
      'u1': TeamRole.player,
      'u2': TeamRole.player,
    });
    events.events['e1'] = TeamEvent(
      id: 'e1',
      title: 'Practice',
      startsAt: DateTime(2026, 11, 2, 18),
      poll: poll,
      rsvps: const {'owner': RsvpStatus.going},
    );
  });

  EventDetailViewModel detail() => EventDetailViewModel(
    teamId: 't1',
    eventId: 'e1',
    eventRepository: events,
    teamRepository: teams,
    authRepository: auth,
  );

  group('EventDetailViewModel', () {
    test('RSVP updates my status and the no-reply list', () async {
      final vm = detail();
      await pumpEventQueue();
      expect(vm.canEdit, isFalse);
      expect(vm.myRsvp, isNull);
      expect(vm.noResponse, hasLength(2));

      await vm.setRsvp.execute(RsvpStatus.maybe);
      await pumpEventQueue();
      expect(vm.myRsvp, RsvpStatus.maybe);
      expect(vm.noResponse, hasLength(1));

      await vm.setRsvp.execute(null);
      await pumpEventQueue();
      expect(vm.myRsvp, isNull);
    });

    test('only attendees can react or vote', () async {
      final vm = detail();
      await pumpEventQueue();
      await vm.toggleReaction.execute(Reaction.fire);
      expect(vm.toggleReaction.error, isTrue);
      await vm.vote.execute('a');
      expect(vm.vote.error, isTrue);
      expect(events.events['e1']!.reactions, isEmpty);
    });

    test('leaving "going" drops my reactions and votes', () async {
      final vm = detail();
      await pumpEventQueue();
      await vm.setRsvp.execute(RsvpStatus.going);
      await pumpEventQueue();
      await vm.toggleReaction.execute(Reaction.fire);
      await vm.vote.execute('a');
      await pumpEventQueue();
      await vm.setRsvp.execute(RsvpStatus.maybe);
      await pumpEventQueue();
      expect(vm.myReactions, isEmpty);
      expect(events.events['e1']!.votes.containsKey('u1'), isFalse);
    });

    test('reactions toggle', () async {
      final vm = detail();
      await pumpEventQueue();
      await vm.setRsvp.execute(RsvpStatus.going);
      await pumpEventQueue();
      await vm.toggleReaction.execute(Reaction.fire);
      await pumpEventQueue();
      expect(vm.myReactions, {Reaction.fire});
      expect(vm.reactions[Reaction.fire], hasLength(1));

      await vm.toggleReaction.execute(Reaction.fire);
      await pumpEventQueue();
      expect(vm.myReactions, isEmpty);
      expect(vm.reactions, isEmpty);
    });

    test(
      'single-choice polls replace the vote; tapping again clears it',
      () async {
        final vm = detail();
        await pumpEventQueue();
        await vm.setRsvp.execute(RsvpStatus.going);
        await pumpEventQueue();
        await vm.vote.execute('a');
        await pumpEventQueue();
        await vm.vote.execute('b');
        await pumpEventQueue();
        expect(events.events['e1']!.votes['u1'], ['b']);
        expect(vm.pollTally.map((t) => t.mine), [false, true]);

        await vm.vote.execute('b');
        await pumpEventQueue();
        expect(events.events['e1']!.votes.containsKey('u1'), isFalse);
      },
    );

    test('multi-choice polls accumulate votes', () async {
      events.events['e1'] = events.events['e1']!.copyWith(
        poll: () => const EventPoll(
          question: 'Which days?',
          options: [
            PollOption(id: 'a', text: 'Sat'),
            PollOption(id: 'b', text: 'Sun'),
          ],
          multiple: true,
        ),
      );
      final vm = detail();
      await pumpEventQueue();
      await vm.setRsvp.execute(RsvpStatus.going);
      await pumpEventQueue();
      await vm.vote.execute('a');
      await pumpEventQueue();
      await vm.vote.execute('b');
      await pumpEventQueue();
      expect(events.events['e1']!.votes['u1'], ['a', 'b']);
    });
  });

  group('EventEditorViewModel', () {
    EventEditorViewModel editor(String? id, {DateTime? day}) =>
        EventEditorViewModel(
          teamId: 't1',
          eventId: id,
          eventRepository: events,
          authRepository: auth,
          initialDay: day,
        );

    test('new events default to 6 PM on the chosen day', () async {
      final vm = editor(null, day: DateTime(2026, 12, 5));
      await pumpEventQueue();
      expect(vm.initial.startsAt, DateTime(2026, 12, 5, 18));
    });

    test('changing poll options clears votes; other edits keep them', () async {
      final vm = editor('e1');
      await pumpEventQueue();
      expect(vm.initial.title, 'Practice');

      await vm.save.execute(vm.initial.copyWith(title: 'Track'));
      expect(events.lastClearVotes, isFalse);

      await vm.save.execute(
        vm.initial.copyWith(
          poll: () => const EventPoll(
            question: 'Jerseys?',
            options: [PollOption(id: 'a', text: 'Dark')],
          ),
        ),
      );
      expect(events.lastClearVotes, isTrue);
    });
  });

  test(
    'TeamDetailViewModel splits upcoming events and events by day',
    () async {
      events.events['old'] = TeamEvent(
        id: 'old',
        title: 'Last week',
        startsAt: DateTime(2026, 10, 20, 18),
      );
      final vm = TeamDetailViewModel(
        teamId: 't1',
        teamRepository: teams,
        playRepository: FakePlayRepository(),
        eventRepository: events,
        authRepository: auth,
        clock: () => DateTime(2026, 10, 28),
      );
      await pumpEventQueue();
      expect(vm.events.map((e) => e.id), ['old', 'e1']);
      expect(vm.upcomingEvents.map((e) => e.id), ['e1']);
      expect(vm.eventsOn(DateTime(2026, 11, 2)).map((e) => e.id), ['e1']);
    },
  );
}
