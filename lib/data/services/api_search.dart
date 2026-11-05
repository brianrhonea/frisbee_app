import 'callable_client.dart';
import 'feature_flags.dart';

/// What `api-search` looks in (functions/src/api).
enum SearchKind { players, people, teams }

/// One document the search found: its id and its data, with timestamps as
/// DateTime like `plainData` gives.
typedef SearchHit = ({String id, Map<String, dynamic> data});

/// Search through the rate-limited `api-search` Cloud Function, so the
/// directory can't be scraped in bulk. Used while the `use_api_search`
/// flag is on; repositories query Firestore directly otherwise.
class ApiSearch {
  ApiSearch({required CallableClient functions, required FeatureFlags flags})
    : _functions = functions,
      _flags = flags;

  final CallableClient _functions;
  final FeatureFlags _flags;

  bool get enabled => _flags.useApiSearch;

  /// Documents whose keywords (or, for players, tags) contain [key]: the
  /// longest word of the query, as the repositories already pick it.
  Future<List<SearchHit>> search(SearchKind kind, String key) async {
    final result = await _functions.call('api-search', {
      'kind': kind.name,
      'key': key,
    });
    final hits = result is Map ? result['results'] : null;
    if (hits is! List) {
      throw const CallableException("The search answer made no sense.");
    }
    return [
      for (final h in hits)
        if (h is Map && h['id'] is String && h['data'] is Map)
          (
            id: h['id'] as String,
            data: _plain(h['data']) as Map<String, dynamic>,
          ),
    ];
  }

  /// Undoes the function's JSON encoding: `{__ts: millis}` → DateTime.
  static Object? _plain(Object? value) => switch (value) {
    {'__ts': final int ms} when value.length == 1 =>
      DateTime.fromMillisecondsSinceEpoch(ms),
    Map m => <String, dynamic>{
      for (final MapEntry(:key, :value) in m.entries) '$key': _plain(value),
    },
    List l => l.map(_plain).toList(),
    _ => value,
  };
}
