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
