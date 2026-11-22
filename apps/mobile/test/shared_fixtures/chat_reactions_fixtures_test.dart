// Shared vectors for chat reactions (quickReactions, reactionGroups and
// isChatReaction in lib/domain/models/chat.dart), checked by
// packages/shared/test/chat_reactions_fixtures.test.ts against
// chat_reactions.ts. See fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/chat.dart';

import 'fixture_file.dart';

const _inputs = [
  '❤️', '‼️', '❓', '👍🏽', '🇺🇸', '🥏', '👨‍👩‍👧', '😀😀', //
  '', ' ', 'a', '1', '#', '1️⃣', '❤️a', 'ok 👍', '😀😀😀😀😀😀😀😀😀',
];

void main() {
  test('chat reactions', () {
    checkFixture(
      'chat_reactions/choices.json',
      'The emoji offered on a '
          'message and which strings count as a reaction.',
      [
        {
          'name': 'offered',
          'quick': quickReactions,
          'groups': [
            for (final (name, emoji) in reactionGroups)
              {'name': name, 'emoji': emoji},
          ],
        },
        for (final s in _inputs)
          {'name': 'is "$s" a reaction', 'input': s, 'ok': isChatReaction(s)},
      ],
    );
  });

  test('everything offered is a reaction', () {
    for (final e in [
      ...quickReactions,
      for (final g in reactionGroups) ...g.$2,
    ]) {
      expect(isChatReaction(e), isTrue, reason: e);
    }
  });
}
