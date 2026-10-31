/// Parses dates coming from the data layer.
///
/// Services convert Firestore `Timestamp`s to [DateTime] before handing maps
/// to models, so domain models stay free of Firebase types. ISO strings and
/// epoch millis are accepted as well.
DateTime? parseDate(Object? value) => switch (value) {
  DateTime d => d,
  String s => DateTime.tryParse(s),
  int ms => DateTime.fromMillisecondsSinceEpoch(ms),
  _ => null,
};

T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// Every prefix of every word in [text], lowercased, so a search for "jo"
/// or "smi" finds "Jo Smith". Capped to keep the document small. Stored as
/// `keywords` for directory searches (people, teams).
List<String> searchKeywords(String text) {
  final words = searchWords(text);
  return {
    for (final w in words)
      for (var i = 1; i <= w.length && i <= 20; i++) w.substring(0, i),
  }.take(100).toList();
}

/// Lowercased words of a name or search query.
List<String> searchWords(String text) => text
    .toLowerCase()
    .split(RegExp(r'[\s\-_.]+'))
    .where((w) => w.isNotEmpty)
    .toList();

/// Whether every word of [query] starts a word of [text].
bool matchesSearch(String text, String query) {
  final words = searchWords(text);
  return searchWords(query).every((q) => words.any((w) => w.startsWith(q)));
}
