import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/play.dart';
import 'package:frisbee_app/domain/models/team_event.dart';

void main() {
  group('TeamEvent', () {
    test('fromMap parses responses and ignores unknown values', () {
      final e = TeamEvent.fromMap('e1', {
        'title': 'Practice',
        'type': 'game',
        'startsAt': DateTime(2026, 11, 2, 18),
        'endsAt': null,
        'poll': {
          'question': 'Jerseys?',
          'options': [
            {'id': 'a', 'text': 'Dark'},
            {'id': 'b', 'text': 'Light'},
          ],
          'multiple': true,
        },
        'rsvps': {'u1': 'going', 'u2': 'maybe', 'u3': 'bogus'},
        'reactions': {
          'u1': ['fire', 'skull'],
          'u2': ['fire', 'clap'],
        },
        'votes': {
          'u1': ['a', 'b'],
          'u2': ['a'],
        },
      });
      expect(e.type, EventType.game);
      expect(e.rsvps, {'u1': RsvpStatus.going, 'u2': RsvpStatus.maybe});
      expect(e.responders(RsvpStatus.going), ['u1']);
      expect(e.reactionTally, {
        Reaction.fire: ['u1', 'u2'],
        Reaction.clap: ['u2'],
      });
      expect(e.poll!.multiple, isTrue);
      expect(e.votersFor('a'), ['u1', 'u2']);
      expect(e.voterCount, 2);
    });

    test('toEditableMap round-trips details but not responses', () {
      final e = TeamEvent(
        id: 'e1',
        title: 'Social',
        type: EventType.social,
        startsAt: DateTime(2026, 11, 2, 18),
        endsAt: DateTime(2026, 11, 2, 21),
        location: 'Park',
        poll: const EventPoll(
          question: 'Food?',
          options: [
            PollOption(id: 'a', text: 'Tacos'),
            PollOption(id: 'b', text: 'Pizza'),
          ],
        ),
        rsvps: const {'u1': RsvpStatus.going},
      );
      final map = e.toEditableMap();
      expect(map.containsKey('rsvps'), isFalse);
      final back = TeamEvent.fromMap('e1', map);
      expect(back.title, 'Social');
      expect(back.endsAt, DateTime(2026, 11, 2, 21));
      expect(back.poll!.options.map((o) => o.text), ['Tacos', 'Pizza']);
    });
  });

  group('Play timeline', () {
    const play = Play(
      id: 'p',
      name: 'Ho stack',
      elements: [
        PlayElement(
          id: 'a',
          kind: ElementKind.offense,
          position: FieldPoint(0, 0),
        ),
        PlayElement(
          id: 'b',
          kind: ElementKind.offense,
          position: FieldPoint(1, 1),
        ),
      ],
      steps: [
        PlayStep(
          id: 's1',
          paths: {
            'a': [FieldPoint(0, 1), FieldPoint(1, 1)],
          },
        ),
        PlayStep(
          id: 's2',
          paths: {
            'b': [FieldPoint(1, 0)],
          },
        ),
      ],
    );

    test('positionsAfter chains steps', () {
      expect(play.positionsAfter(0)['a'], const FieldPoint(0, 0));
      expect(play.positionsAfter(1)['a'], const FieldPoint(1, 1));
      expect(play.positionsAfter(2)['b'], const FieldPoint(1, 0));
    });

    test('positionsAt interpolates by arc length with easing', () {
      // Halfway through step 1 (eased 0.5 is still 0.5) is the path corner.
      expect(play.positionsAt(0.5)['a'], const FieldPoint(0, 1));
      // Non-movers hold.
      expect(play.positionsAt(0.5)['b'], const FieldPoint(1, 1));
      final mid = play.positionsAt(1.5)['b']!;
      expect(mid.x, 1);
      expect(mid.y, closeTo(0.5, 1e-9));
      expect(play.positionsAt(99)['b'], const FieldPoint(1, 0));
    });

    test('steps survive serialization', () {
      final back = Play.fromMap('p', play.toMap());
      expect(back.steps, hasLength(2));
      expect(back.steps.first.paths['a'], [
        const FieldPoint(0, 1),
        const FieldPoint(1, 1),
      ]);
      expect(back.positionsAfter(2), play.positionsAfter(2));
    });

    test('old plays without steps still load', () {
      final back = Play.fromMap('p', {'name': 'Static'});
      expect(back.steps, isEmpty);
      expect(back.positionsAt(1), isEmpty);
    });
  });
}
