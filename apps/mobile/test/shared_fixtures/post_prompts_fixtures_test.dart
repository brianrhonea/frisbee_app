// The composer's rotating hints (domain/models/post_prompts.dart), checked
// by packages/shared/test/post_prompts_fixtures.test.ts against
// post_prompts.ts. See fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/post_prompts.dart';

import 'fixture_file.dart';

void main() {
  test("the composer's prompts (post_prompts/prompts.json)", () {
    checkFixture(
      'post_prompts/prompts.json',
      "The composer's empty-body hints, in order, and which one each turn "
          'shows (going round).',
      [
        for (final turn in [0, 1, 5, 6, 13])
          {'turn': turn, 'prompt': postPrompt(turn), 'all': postPrompts},
      ],
    );
  });
}
