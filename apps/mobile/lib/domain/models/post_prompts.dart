/// The composer's empty-body hint: one of these, a different one each time
/// the composer opens (post_prompts.ts in packages/shared; checked by
/// test/shared_fixtures/post_prompts_fixtures_test.dart). Team, workout and
/// repost posts keep their own hints.
library;

const postPrompts = [
  "What's happening on the field?",
  'How did practice go?',
  'Looking for a pickup game?',
  'Share a highlight from your last game.',
  'Got a question for other players?',
  'What are you working on this week?',
];

/// The [turn]th prompt, going round.
String postPrompt(int turn) => postPrompts[turn % postPrompts.length];
