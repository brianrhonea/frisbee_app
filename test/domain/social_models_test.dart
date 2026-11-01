import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/feed_item.dart';
import 'package:frisbee_app/domain/models/follow.dart';
import 'package:frisbee_app/domain/models/team_post.dart';
import 'package:frisbee_app/domain/models/user_post.dart';
import 'package:frisbee_app/domain/models/workout.dart';

void main() {
  group('FollowTarget', () {
    test('keys match firestore.rules and the Cloud Functions', () {
      expect(const FollowTarget.user('u1', 'Sam').key, 'user_u1');
      expect(const FollowTarget.team('t1', 'Hawks').key, 'team_t1');
      expect(const FollowTarget.event('123', 'Nationals').key, 'event_123');
      expect(
        const FollowTarget.tournament('g1', 'x1', 'Fall Hat').key,
        'tournament_g1_x1',
      );
      expect(FollowTarget.tournamentKey('g1', 'x1'), 'tournament_g1_x1');
    });

    test('round-trips through Firestore, group tournaments included', () {
      const f = Follow(
        target: FollowTarget.tournament('g1', 'x1', 'Fall Hat'),
        notify: true,
      );
      final map = f.toMap();
      expect(map, {
        'key': 'tournament_g1_x1',
        'type': 'tournament',
        'targetId': 'g1_x1',
        'groupId': 'g1',
        'name': 'Fall Hat',
        'notify': true,
      });
      final back = Follow.fromMap(map);
      expect(back.key, f.key);
      expect(back.target.id, 'x1');
      expect(back.target.groupId, 'g1');
      expect(back.notify, isTrue);
    });

    test('names are capped like the rules', () {
      final map = Follow(target: FollowTarget.team('t', 'x' * 150)).toMap();
      expect((map['name'] as String).length, Follow.maxNameLength);
    });
  });

  group('Workout', () {
    test('validates like the rules', () {
      expect(const Workout(durationMinutes: 30).isValid, isTrue);
      expect(const Workout().problem, isNotNull);
      expect(
        const Workout(durationMinutes: 30, distanceKm: -1).isValid,
        isFalse,
      );
      expect(const Workout(durationMinutes: 30, effort: 11).isValid, isFalse);
      expect(
        const Workout(
          durationMinutes: 30,
          exercises: [WorkoutExercise(name: '')],
        ).isValid,
        isFalse,
      );
      expect(
        Workout(
          durationMinutes: 30,
          exercises: List.filled(21, const WorkoutExercise(name: 'Squat')),
        ).isValid,
        isFalse,
      );
    });

    test('labels time, distance and pace', () {
      const w = Workout(durationMinutes: 50, distanceKm: 10);
      expect(w.durationLabel, '50 min');
      expect(const Workout(durationMinutes: 90).durationLabel, '1 h 30 min');
      expect(const Workout(durationMinutes: 120).durationLabel, '2 h');
      expect(w.distanceLabel, '10 km');
      expect(const Workout(distanceKm: 5.25).distanceLabel, '5.3 km');
      expect(w.paceLabel, '5:00 /km');
      expect(
        const WorkoutExercise(
          name: 'Squat',
          sets: 3,
          reps: 5,
          weight: '100 kg',
        ).detail,
        '3 × 5 @ 100 kg',
      );
      expect(const WorkoutExercise(name: 'Plank').detail, '');
    });
  });

  group('UserPost', () {
    test('round-trips a workout post', () {
      const post = UserPost(
        id: 'p1',
        body: 'Legs',
        workout: Workout(
          activity: WorkoutActivity.gym,
          durationMinutes: 60,
          effort: 7,
          exercises: [WorkoutExercise(name: 'Squat', sets: 3, reps: 5)],
        ),
        tournamentKey: 'event_1',
        tournamentName: 'Nationals',
      );
      final map = post.toEditableMap();
      expect(map['kind'], 'workout');
      final back = UserPost.fromMap('p1', map);
      expect(back.kind, UserPostKind.workout);
      expect(back.workout!.exercises.single.reps, 5);
      expect(back.tournamentName, 'Nationals');
    });

    test('text posts write null workout and tag so edits can clear them', () {
      final map = const UserPost(id: '', body: 'Hi').toEditableMap();
      expect(map['kind'], 'text');
      expect(map.containsKey('workout'), isTrue);
      expect(map['workout'], isNull);
      expect(map['tournamentKey'], isNull);
    });

    test('a workout alone is content', () {
      expect(const UserPost(id: '').hasContent, isFalse);
      expect(
        const UserPost(id: '', workout: Workout(durationMinutes: 5)).hasContent,
        isTrue,
      );
    });
  });

  test('TeamPost keeps its tournament tag', () {
    final p = TeamPost.fromMap('p', {
      'body': 'Sign up',
      'tournamentKey': 'tournament_g1_x1',
    });
    expect(p.tournamentKey, 'tournament_g1_x1');
    expect(p.toEditableMap()['tournamentKey'], 'tournament_g1_x1');
    expect(
      const TeamPost(id: '').toEditableMap().containsKey('tournamentKey'),
      isFalse,
    );
  });

  test('mergeFeed sorts newest first, dedupes and limits', () {
    UserPostItem u(String id, int day) =>
        UserPostItem(UserPost(id: id, createdAt: DateTime(2026, 10, day)));
    final team = TeamPostItem(
      teamId: 't',
      teamName: 'Hawks',
      post: TeamPost(id: 'x', createdAt: DateTime(2026, 10, 3)),
    );
    final merged = mergeFeed([
      [u('a', 1), u('b', 5)],
      [team, u('a', 1)],
      [UserPostItem(const UserPost(id: 'pending'))],
    ], limit: 3);
    expect(merged.map((i) => i.id), ['user/pending', 'user/b', 'team/t/x']);
  });
}
