import 'team.dart';

/// Team names must be unique: two teams can't share a name (or a
/// near-identical one, like "TX BQQ" and "Texas BQQ") unless their
/// divisions differ. Groups and communities can't share one with another
/// of their kind.

/// US state and DC abbreviations, so "TX" and "Texas" match.
const _states = {
  'al': 'alabama',
  'ak': 'alaska',
  'az': 'arizona',
  'ar': 'arkansas',
  'ca': 'california',
  'cali': 'california',
  'co': 'colorado',
  'ct': 'connecticut',
  'de': 'delaware',
  'fl': 'florida',
  'ga': 'georgia',
  'hi': 'hawaii',
  'id': 'idaho',
  'il': 'illinois',
  'in': 'indiana',
  'ia': 'iowa',
  'ks': 'kansas',
  'ky': 'kentucky',
  'la': 'louisiana',
  'me': 'maine',
  'md': 'maryland',
  'ma': 'massachusetts',
  'mass': 'massachusetts',
  'mi': 'michigan',
  'mn': 'minnesota',
  'ms': 'mississippi',
  'mo': 'missouri',
  'mt': 'montana',
  'ne': 'nebraska',
  'nv': 'nevada',
  'nh': 'newhampshire',
  'nj': 'newjersey',
  'nm': 'newmexico',
  'ny': 'newyork',
  'nc': 'northcarolina',
  'nd': 'northdakota',
  'oh': 'ohio',
  'ok': 'oklahoma',
  'or': 'oregon',
  'pa': 'pennsylvania',
  'penn': 'pennsylvania',
  'ri': 'rhodeisland',
  'sc': 'southcarolina',
  'sd': 'southdakota',
  'tn': 'tennessee',
  'tx': 'texas',
  'tex': 'texas',
  'ut': 'utah',
  'vt': 'vermont',
  'va': 'virginia',
  'wa': 'washington',
  'wv': 'westvirginia',
  'wi': 'wisconsin',
  'wy': 'wyoming',
  'dc': 'washingtondc',
};

/// Two-word state names, joined so "New York" matches "NY".
const _twoWordStates = {
  'new hampshire',
  'new jersey',
  'new mexico',
  'new york',
  'north carolina',
  'north dakota',
  'rhode island',
  'south carolina',
  'south dakota',
  'west virginia',
};

/// Other spellings that mean the same thing in a team name.
const _aliases = {
  'univ': 'university',
  'uni': 'university',
  'u': 'university',
  'st': 'saint',
  'n': 'and',
};

/// Words too common to tell teams apart; searched only when a name has
/// nothing else.
const _common = {
  'the',
  'and',
  'of',
  'ultimate',
  'frisbee',
  'disc',
  'club',
  'team',
  'fc',
  'university',
  'college',
  'school',
  'high',
  'mixed',
  'open',
  'women',
  'womens',
  'masters',
};

/// The words of [name], lowercased, without punctuation, with
/// abbreviations spelled out: "TX B.Q.Q." → `[texas, bqq]`.
List<String> teamNameWords(String name) {
  var text = name.toLowerCase().replaceAll('&', ' and ');
  // "B.Q.Q." and "B-Q-Q" are one word; other punctuation splits words.
  text = text.replaceAllMapped(
    RegExp(r'\b(?:[a-z0-9][.\-]){1,}[a-z0-9]\b\.?'),
    (m) => m[0]!.replaceAll(RegExp(r'[.\-]'), ''),
  );
  text = text.replaceAll(RegExp(r"['’]"), '');
  text = text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  for (final s in _twoWordStates) {
    text = text.replaceAll(RegExp('\\b$s\\b'), s.replaceAll(' ', ''));
  }
  final words = [
    for (final w in text.split(' '))
      if (w.isNotEmpty) _states[w] ?? _aliases[w] ?? w,
  ];
  // "The Haze" and "Haze" are the same team.
  if (words.length > 1 && words.first == 'the') words.removeAt(0);
  return words;
}

/// What a name is compared by: [teamNameWords] run together, so spacing
/// doesn't matter either ("BQQ" and "B QQ").
String teamNameKey(String name) => teamNameWords(name).join();

/// Whether [name] for a [kind] team in [division] is taken by [listing].
bool teamNameClashes(
  TeamListing listing, {
  required String name,
  required TeamKind kind,
  required Division division,
  String? excludeId,
}) {
  if (listing.id == excludeId) return false;
  if (listing.kind != kind) return false;
  // Teams in different divisions can share a name; groups have none.
  if (kind == TeamKind.team && listing.division != division) return false;
  final key = teamNameKey(name);
  return key.isNotEmpty && teamNameKey(listing.name) == key;
}

/// The search keywords to look for a name's possible clashes by: its most
/// distinctive word, in every spelling a listing's keywords could hold it.
List<String> teamNameProbe(String name) {
  final words = teamNameWords(name);
  if (words.isEmpty) return const [];
  // States are shared by many teams; anything else tells them apart better.
  final stateNames = _states.values.toSet();
  var distinctive = [
    for (final w in words)
      if (!_common.contains(w) && !stateNames.contains(w)) w,
  ];
  if (distinctive.isEmpty) {
    distinctive = [
      for (final w in words)
        if (!_common.contains(w)) w,
    ];
  }
  final pick = (distinctive.isEmpty ? words : distinctive).reduce(
    (a, b) => b.length > a.length ? b : a,
  );
  // Listing keywords are prefixes of the words as typed, so also look for
  // the abbreviations and the first word of two-word states.
  return {
    _clip(pick),
    for (final MapEntry(:key, :value) in {..._states, ..._aliases}.entries)
      if (value == pick) _clip(key),
    for (final s in _twoWordStates)
      if (s.replaceAll(' ', '') == pick) s.split(' ').first,
  }.take(10).toList();
}

String _clip(String w) => w.length > 20 ? w.substring(0, 20) : w;

/// Another team, group or community already has that name.
class TeamNameTakenException implements Exception {
  const TeamNameTakenException(this.name, this.kind, this.division);

  final String name;
  final TeamKind kind;
  final Division division;

  @override
  String toString() => kind == TeamKind.team
      ? 'There\'s already a ${division.label} team called "$name". '
            'Pick a different name.'
      : 'There\'s already a ${kind.label.toLowerCase()} called "$name". '
            'Pick a different name.';
}
