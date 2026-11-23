// @mentions (lib/domain/models/mentions.dart), checked by
// packages/shared/test/mention_fixtures.test.ts against mentions.ts. See
// fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/mentions.dart';

import 'fixture_file.dart';

const _members = [
  ('u1', 'Sam'),
  ('u2', 'Sam Lee'),
  ('u3', 'Avery Jones'),
  ('u4', 'José Núñez'),
  ('u5', 'avery'),
];
const _roles = [('r1', 'Handlers'), ('r2', 'Cutters'), ('r3', 'Sam')];

MentionTargets get _targets => MentionTargets(
  members: {for (final (id, n) in _members) id: n},
  roles: {for (final (id, n) in _roles) id: n},
);

const _texts = [
  'hi @Sam',
  '@Sam Lee are you in?',
  '@sam lee, and @AVERY JONES!',
  'email me at sam@example.com',
  '@everyone practice moved',
  '@everyones',
  '@Handlers and @Cutters line up',
  '(@José Núñez)',
  '@Samuel',
  '@@Sam',
  'no mentions here',
  '@avery and @Avery Jones',
  '@Sam @Sam @Sam',
];

const _queries = [
  ('hey @', 5),
  ('hey @Sa', 7),
  ('hey @Sam Le', 11),
  ('mail sam@ex', 11),
  ('@ever', 5),
  ('@ ', 2),
  ('two @a @b', 9),
  ('no at', 5),
];

void main() {
  test('mentions (mentions/cases.json)', () {
    Map<String, Object?> spans(String text) => {
      'text': text,
      'spans': [
        for (final s in mentionSpans(text, _targets))
          {'start': s.start, 'end': s.end, 'kind': s.kind.name, 'id': s.id},
      ],
      'mentions': mentionsIn(text, _targets, canMentionGroups: true).toMap(),
      'mentionsNoGroups': mentionsIn(
        text,
        _targets,
        canMentionGroups: false,
      ).toMap(),
    };
    checkFixture(
      'mentions/cases.json',
      'Team chat @mentions: the spans a text has, what it mentions (with and '
          'without @everyone and roles), the @query at a cursor, '
          'suggestions, and inserting one. Targets: members and roles in '
          'order.',
      [
        {
          'members': [
            for (final (id, n) in _members) {'uid': id, 'name': n},
          ],
          'roles': [
            for (final (id, n) in _roles) {'id': id, 'name': n},
          ],
        },
        for (final t in _texts) spans(t),
        for (final (text, cursor) in _queries)
          {
            'query': text,
            'cursor': cursor,
            'found': switch (mentionQuery(text, cursor)) {
              null => null,
              final q => {'start': q.start, 'query': q.query},
            },
          },
        for (final q in ['', 'sa', 'av', 'h', 'jo', 'ev', 'zz'])
          for (final groups in [true, false])
            {
              'suggest': q,
              'groups': groups,
              'results': [
                for (final s in mentionSuggestions(
                  q,
                  _targets,
                  canMentionGroups: groups,
                ))
                  {'kind': s.kind.name, 'id': s.id, 'label': s.label},
              ],
            },
        {
          'insert': 'hey @Sa now',
          'start': 4,
          'cursor': 7,
          'label': 'Sam Lee',
          'result': () {
            final r = insertMention('hey @Sa now', 4, 7, 'Sam Lee');
            return {'text': r.text, 'cursor': r.cursor};
          }(),
        },
      ],
    );
  });

  test('a stored mentions map reaches people by name, role or everyone', () {
    final m = Mentions.fromMap({
      'users': ['u1'],
      'roles': ['r1'],
      'everyone': false,
    });
    expect(m.reaches('u1', const []), isTrue);
    expect(m.reaches('u2', const ['r1']), isTrue);
    expect(m.reaches('u2', const ['r2']), isFalse);
    expect(Mentions.fromMap(null).any, isFalse);
    expect(const Mentions(everyone: true).reaches('x', const []), isTrue);
  });
}
