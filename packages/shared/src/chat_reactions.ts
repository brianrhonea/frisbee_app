// Chat reactions (iMessage-style tapbacks): the quick ones in the bubble a
// double-tap opens, the rest behind its +, and what counts as a reaction.
// The app has the same in lib/domain/models/chat.dart (quickReactions,
// reactionGroups, isChatReaction); fixtures/chat_reactions keeps them in step.

/** The quick reactions offered on a message. */
export const chatQuickReactions = ["❤️", "👍", "👎", "😂", "‼️", "❓"] as const;

/** Behind the +: more emoji, by group. Single emoji only (no skin tones or joined sequences). */
export const chatReactionGroups: readonly { name: string; emoji: readonly string[] }[] = [
  {
    name: "Smileys",
    emoji: [
      "😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂", "😉", "😊", "😇",
      "🥰", "😍", "🤩", "😘", "😋", "😛", "😜", "🤪", "😎", "🤓", "🧐", "🤔",
      "🤨", "😐", "😑", "😶", "🙄", "😏", "😬", "😮", "😯", "😲", "😳", "🥺",
      "😢", "😭", "😤", "😠", "😡", "🤯", "😱", "😨", "😰", "😴", "🤤", "🤢",
      "🤮", "🥵", "🥶", "🥴", "😵", "🤠", "🥳", "🤗", "🤫", "🤭", "🫡", "💀",
    ],
  },
  {
    name: "Hands",
    emoji: [
      "👍", "👎", "👏", "🙌", "👐", "🤲", "🙏", "🤝", "✌️", "🤞", "🤟", "🤘",
      "👌", "🤌", "👈", "👉", "👆", "👇", "☝️", "✋", "🤚", "🖐️", "👋", "💪",
      "🫶", "👀", "🧠",
    ],
  },
  {
    name: "Hearts",
    emoji: ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "❣️"],
  },
  {
    name: "Game day",
    emoji: [
      "🥏", "🏃", "🏆", "🥇", "🥈", "🥉", "🏅", "🎯", "⚡", "🔥", "💨", "💦",
      "☀️", "🌧️", "⛈️", "🌈", "❄️", "🏟️", "🧢", "👟", "⏱️", "📣", "🎉", "🎊",
    ],
  },
  {
    name: "Animals and food",
    emoji: [
      "🐐", "🦅", "🐝", "🦈", "🐻", "🐶", "🐱", "🦁", "🐯", "🐺", "🦊", "🐸",
      "🐢", "🦆", "🐔", "🍕", "🍔", "🌮", "🍩", "🍪", "🍉", "🍌", "🍺", "☕",
      "🧃", "💧",
    ],
  },
  {
    name: "Symbols",
    emoji: [
      "‼️", "❓", "❗", "⁉️", "💯", "✅", "❌", "⭕", "🚫", "⚠️", "💤", "💬",
      "👑", "💎", "🚀", "⭐", "🌟", "✨", "💥", "🎶", "📅", "📍",
    ],
  },
];

/** Longest reaction stored (UTF-16 code units), as firestore.rules reactsOnlyAsMe(). */
export const chatReactionMax = 16;

const emojiOnly = /^(?:\p{Extended_Pictographic}|\p{Emoji_Component}|‍|️)+$/u;
const pictograph = /\p{Extended_Pictographic}|[\u{1F1E6}-\u{1F1FF}]/u;

/** One emoji (or the few pieces one is made of, like a flag or a skin tone), nothing else. */
export function isChatReaction(s: string): boolean {
  return s.length > 0 && s.length <= chatReactionMax && emojiOnly.test(s) && pictograph.test(s);
}
