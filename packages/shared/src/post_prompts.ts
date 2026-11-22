// The composer's empty-body hint (Home's composer on both platforms): one
// of these, a different one each time the composer opens, so posting has
// a nudge. Team, workout and repost posts keep their own hints. Keep in
// step with apps/mobile/lib/domain/models/post_prompts.dart (fixtures in
// fixtures/post_prompts).
export const postPrompts = [
  "What's happening on the field?",
  "How did practice go?",
  "Looking for a pickup game?",
  "Share a highlight from your last game.",
  "Got a question for other players?",
  "What are you working on this week?",
] as const;

/** The [turn]th prompt, going round. */
export const postPrompt = (turn: number) => postPrompts[((turn % postPrompts.length) + postPrompts.length) % postPrompts.length]!;
