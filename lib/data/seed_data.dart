import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../models/drill.dart';
import 'hive_boxes.dart';

final _uuid = Uuid();

Future<void> seedIfNeeded() async {
  final box = Hive.box(HiveBoxes.drills);
  if (box.isNotEmpty) return;

  final drills = <Drill>[
    Drill(
      id: _uuid.v4(),
      title: 'Partner Throwing Ladder',
      category: 'Throwing',
      minPlayers: 2,
      maxPlayers: 40,
      suggestedMinutes: 10,
      intensity: 2,
      skills: ['Backhand', 'Flick', 'Footwork'],
      setup: 'Pairs, 10–30 yards apart. One disc per pair.',
      steps: '1) 10 throws each\n2) Add pivot fakes\n3) Increase distance',
      coachingPoints: 'Snap, follow-through, balanced pivots.',
      variations: 'Add IO-only round, add mark, add hucks.',
    ),
    Drill(
      id: _uuid.v4(),
      title: '3-Cone Cutting (In/Out)',
      category: 'Cutting',
      minPlayers: 3,
      maxPlayers: 12,
      suggestedMinutes: 12,
      intensity: 3,
      skills: ['Timing', 'Acceleration', 'Separation'],
      setup: 'Three cones in a line, handler at disc, cutter starts middle.',
      steps: '1) Hard in-cut, reset\n2) Hard out-cut\n3) Add defender later',
      coachingPoints: 'Sell the first move, shoulder fake, explode.',
      variations: 'Add dump swing, add live continuation.',
    ),
    Drill(
      id: _uuid.v4(),
      title: 'Marking Fundamentals (No-Disc)',
      category: 'Defense',
      minPlayers: 2,
      maxPlayers: 20,
      suggestedMinutes: 8,
      intensity: 3,
      skills: ['Stance', 'Mirroring', 'Balance'],
      setup: 'Pairs. One is marker, one is thrower (no disc).',
      steps: '1) Mirror pivots\n2) Add quick fakes\n3) Switch roles',
      coachingPoints: 'Stay low, active hands, don’t cross feet.',
      variations: 'Add disc, force flick/backhand rounds.',
    ),
  ];

  for (final d in drills) {
    await box.put(d.id, d.toMap());
  }
}
