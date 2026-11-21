/// The word filter for everything people write, the same as
/// packages/shared/src/word_filter.ts (the API's copy): slurs, hate terms
/// and "kill yourself" are refused ([blockedWordsMessage]); mild swearing is
/// kept but masked ("f***"). Words are matched whole after lower-casing and
/// undoing look-alikes, with common endings and stretched letters; letters
/// spaced or dotted out are checked against the blocked list.
///
/// The lists and cases live in packages/shared/fixtures/word_filter/, which
/// test/domain/word_filter_test.dart checks this against: change both
/// sides together.
library;

import '../../utils/result.dart';

/// Refused outright.
const blockedTerms = <String>[
  'beaner',
  'fag',
  'faggot',
  'gook',
  'jigaboo',
  'kike',
  'kys',
  'nigga',
  'nigger',
  'paki',
  'raghead',
  'sandnigger',
  'shemale',
  'spic',
  'towelhead',
  'tranny',
  'wetback',
];

/// Refused as phrases (words in order).
const blockedPhrases = <String>[
  'kill yourself',
  'go kill yourself',
  'heil hitler',
  'sieg heil',
  'white power',
];

/// Shown masked: mild swearing and insults.
const maskedTerms = <String>[
  'arse',
  'arsehole',
  'ass',
  'asshat',
  'asshole',
  'bastard',
  'bitch',
  'bollocks',
  'bullshit',
  'chink',
  'cock',
  'cocksucker',
  'coon',
  'cunt',
  'dick',
  'dickhead',
  'dipshit',
  'dumbass',
  'dyke',
  'fuck',
  'fucker',
  'fuckface',
  'fuckhead',
  'goddamn',
  'horseshit',
  'jackass',
  'motherfucker',
  'piss',
  'prick',
  'pussy',
  'retard',
  'shit',
  'shithead',
  'slut',
  'twat',
  'wanker',
  'whore',
];

/// Endings a masked word may take (not "y" or "er": "cocky").
const maskedEndings = <String>['s', 'es', 'ed', 'ing', 'in', 'ty', 'z'];

/// Endings a blocked word may take: plurals only ("spicy" is fine).
const blockedEndings = <String>['s', 'es', 'z'];

/// What the app (and the API) says when text has a blocked word.
const blockedWordsMessage =
    "That includes words that aren't allowed on Stall 10. See the community "
    'guidelines.';

const _lookAlikes = {
  '0': 'o',
  '1': 'i',
  '3': 'e',
  '4': 'a',
  '5': 's',
  '7': 't',
  '@': 'a',
  r'$': 's',
  '!': 'i',
  '|': 'i',
};

final _token = RegExp(r'[\p{L}\p{N}@$!|]+', unicode: true);
final _letter = RegExp(r'\p{L}', unicode: true);
final _trailing = RegExp(r'[!|]+$');
final _repeats = RegExp(r'(\p{L})\1+', unicode: true);

/// [word] lower-cased with look-alikes undone; letters only. A trailing
/// "!" or "|" is punctuation, not a letter.
String normalizeWord(String word) {
  final out = StringBuffer();
  for (final r in word.toLowerCase().replaceAll(_trailing, '').runes) {
    final ch = String.fromCharCode(r);
    final c = _lookAlikes[ch] ?? ch;
    if (_letter.hasMatch(c)) out.write(c);
  }
  return out.toString();
}

String _squeeze(String w) => w.replaceAllMapped(_repeats, (m) => m[1]!);

class _Index {
  _Index(List<String> terms, this.endings)
    : exact = terms.toSet(),
      squeezed = {
        for (final t in terms)
          if (_squeeze(t).length >= 4) _squeeze(t),
      };

  final Set<String> exact;
  final Set<String> squeezed;
  final List<String> endings;
}

final _blocked = _Index(blockedTerms, blockedEndings);
final _masked = _Index(maskedTerms, maskedEndings);

bool _hit(String word, Set<String> set, List<String> endings) =>
    set.contains(word) ||
    endings.any(
      (e) =>
          word.length > e.length &&
          word.endsWith(e) &&
          set.contains(word.substring(0, word.length - e.length)),
    );

bool _matches(String word, _Index index) =>
    word.isNotEmpty &&
    (_hit(word, index.exact, index.endings) ||
        _hit(word, index.squeezed, index.endings) ||
        _hit(_squeeze(word), index.squeezed, index.endings));

/// The filter's verdict on some text.
class FilteredText {
  const FilteredText(this.text, {required this.blocked});

  /// The text with mild swearing masked; unchanged when there's none.
  final String text;

  /// Whether it has a blocked word or phrase (refuse it).
  final bool blocked;
}

/// Checks [text]: masks mild swearing and says whether it's blocked.
FilteredText filterText(String text) {
  final toks = _token.allMatches(text).toList();
  final words = [for (final t in toks) normalizeWord(t[0]!)];
  var blocked = words.any((w) => _matches(w, _blocked));
  // Spaced or dotted out: three or more single letters in a row, joined.
  for (var i = 0; !blocked && i < toks.length;) {
    var j = i;
    while (j < toks.length && words[j].length == 1) {
      j++;
    }
    if (j - i >= 3 && _matches(words.sublist(i, j).join(), _blocked)) {
      blocked = true;
    }
    i = j == i ? i + 1 : j;
  }
  if (!blocked) {
    final joined = ' ${words.where((w) => w.isNotEmpty).join(' ')} ';
    blocked = blockedPhrases.any((p) => joined.contains(' $p '));
  }
  final out = StringBuffer();
  var at = 0;
  for (final t in toks) {
    if (!_matches(normalizeWord(t[0]!), _masked)) continue;
    final chars = t[0]!.runes.toList();
    out
      ..write(text.substring(at, t.start))
      ..write(String.fromCharCode(chars.first))
      ..write('*' * (chars.length - 1));
    at = t.end;
  }
  if (at == 0) return FilteredText(text, blocked: blocked);
  out.write(text.substring(at));
  return FilteredText(out.toString(), blocked: blocked);
}

/// Whether [text] has a blocked word or phrase.
bool hasBlockedWords(String text) => filterText(text).blocked;

/// [text] with mild swearing masked.
String maskSwearing(String text) => filterText(text).text;

/// Thrown by a repository refusing text with a blocked word; its message
/// is [blockedWordsMessage].
class BlockedWordsException implements Exception {
  const BlockedWordsException();

  String get message => blockedWordsMessage;

  @override
  String toString() => blockedWordsMessage;
}

/// [text] masked, or throws [BlockedWordsException] when it has a blocked
/// word: what repositories run on text before they save it.
String cleanText(String text) {
  final f = filterText(text);
  if (f.blocked) throw const BlockedWordsException();
  return f.text;
}

/// A refusal to return when any of [texts] has a blocked word; null when
/// they're all fine (then save them through [maskSwearing]).
Future<Result<T>>? refuseBlockedWords<T>(Iterable<String?> texts) =>
    texts.any((t) => t != null && hasBlockedWords(t))
    ? Future.value(Result<T>.error(const BlockedWordsException()))
    : null;
