// Shared vectors for play animation (lib/domain/models/play.dart), checked
// by packages/shared/test/playbook_fixtures.test.ts against playbook.ts.
// See fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/play.dart';

import 'fixture_file.dart';

FieldPoint _p(double x, double y) => FieldPoint(x, y);

PlayElement _e(String id, ElementKind kind, double x, double y) =>
    PlayElement(id: id, kind: kind, position: _p(x, y), label: id);

final _plays = <Play>[
  const Play(
    id: 'static',
    name: 'Static diagram',
    elements: [
      PlayElement(
        id: 'o1',
        kind: ElementKind.offense,
        position: FieldPoint(0.5, 0.5),
      ),
    ],
  ),
  Play(
    id: 'easing',
    name: 'One piece along a straight line',
    elements: [_e('o1', ElementKind.offense, 0, 0.5)],
    steps: [
      PlayStep(
        id: 's1',
        paths: {
          'o1': [_p(1, 0.5)],
        },
      ),
    ],
  ),
  Play(
    id: 'vert',
    name: 'Vert stack: cut, throw, clear',
    elements: [
      _e('h1', ElementKind.offense, 0.5, 0.3),
      _e('c1', ElementKind.offense, 0.5, 0.45),
      _e('c2', ElementKind.offense, 0.5, 0.55),
      _e('d1', ElementKind.defense, 0.52, 0.47),
      _e('disc', ElementKind.disc, 0.5, 0.3),
      _e('cone', ElementKind.cone, 0, 0.18),
    ],
    arrows: [
      PlayArrow(
        id: 'a1',
        kind: ArrowKind.cut,
        points: [_p(0.5, 0.45), _p(0.8, 0.35)],
      ),
    ],
    steps: [
      PlayStep(
        id: 's1',
        note: 'Under cut with a dogleg',
        paths: {
          'c1': [_p(0.6, 0.42), _p(0.8, 0.35)],
          'd1': [_p(0.75, 0.37)],
          // Not on the field: ignored.
          'ghost': [_p(0.1, 0.1)],
        },
      ),
      PlayStep(
        id: 's2',
        note: 'Throw, and nobody else moves',
        paths: {
          'disc': [_p(0.65, 0.33), _p(0.8, 0.35)],
          // An empty path leaves the piece where it is.
          'h1': [],
        },
      ),
      PlayStep(
        id: 's3',
        note: 'Clear out, with a repeated point',
        paths: {
          'c1': [_p(0.8, 0.35), _p(0.9, 0.6), _p(0.9, 0.6), _p(0.6, 0.8)],
          'c2': [_p(0.5, 0.55)],
        },
      ),
    ],
  ),
];

final _paths = <List<FieldPoint>>[
  [_p(0.2, 0.2)],
  [_p(0, 0), _p(1, 1)],
  [_p(0, 0), _p(0.3, 0), _p(0.3, 0.4)],
  [_p(0.5, 0.5), _p(0.5, 0.5)],
  [_p(0.1, 0.9), _p(0.1, 0.9), _p(0.4, 0.5), _p(0.4, 0.5), _p(0.9, 0.5)],
];

const _fractions = [
  -0.5,
  0.0,
  0.1,
  0.25,
  1 / 3,
  0.5,
  0.6,
  0.75,
  0.99,
  1.0,
  1.5,
];

Map<String, Object?> _positions(Map<String, FieldPoint> pos) => {
  for (final e in pos.entries) e.key: e.value.toMap(),
};

void main() {
  test('play animation (playbook/animation.json)', () {
    checkFixture(
      'playbook/animation.json',
      'For each play (Play.toMap with its id): positionsAfter for every '
          'step count, pathIn for every step and moving piece, and '
          'positionsAt at fractions of the timeline (eased).',
      [
        for (final play in _plays)
          {
            'play': {'id': play.id, ...play.toMap()},
            'positionsAfter': [
              for (var s = 0; s <= play.steps.length + 1; s++)
                _positions(play.positionsAfter(s)),
            ],
            'pathIn': [
              for (final (i, st) in play.steps.indexed)
                {
                  for (final id in st.paths.keys)
                    id: [for (final p in play.pathIn(i, id)) p.toMap()],
                },
            ],
            'positionsAt': [
              for (final t in [
                -1.0,
                0.0,
                for (var k = 1; k < play.steps.length * 8; k++) k / 8,
                play.steps.length.toDouble(),
                play.steps.length + 0.5,
              ])
                {'t': t, 'positions': _positions(play.positionsAt(t))},
            ],
          },
      ],
    );
  });

  test('points along a path (playbook/point_along.json)', () {
    checkFixture(
      'playbook/point_along.json',
      'Play.pointAlong(path, f) for each path and fraction.',
      [
        for (final path in _paths)
          {
            'path': [for (final p in path) p.toMap()],
            'points': [
              for (final f in _fractions)
                {'f': f, 'point': Play.pointAlong(path, f).toMap()},
            ],
          },
      ],
    );
  });
}
