import 'dart:convert';
import 'dart:math';

/// Client-chosen ids for creates, kept per identical request until it
/// succeeds, so a retry after a lost response sends the same id and the
/// server answers 409 instead of making a second copy (contracts/
/// phase1-writes.md, review L1).
class PendingIds {
  final _ids = <String, String>{};

  static const _max = 50;

  /// The id for [kind] with [request] (the body, minus its id): the one
  /// already minted for the same request, or a new one from [mint].
  String idFor(String kind, Object? request, String Function() mint) {
    final key = '$kind ${jsonEncode(request)}';
    if (_ids.length >= _max && !_ids.containsKey(key)) {
      _ids.remove(_ids.keys.first);
    }
    return _ids.putIfAbsent(key, mint);
  }

  static final _rng = Random.secure();
  static const _alphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  /// A fresh 20-character id (letters and digits: the API's id shape).
  static String mintId() => String.fromCharCodes([
    for (var i = 0; i < 20; i++)
      _alphabet.codeUnitAt(_rng.nextInt(_alphabet.length)),
  ]);

  /// Forget [id] once the request succeeded (or was a 409).
  void done(String id) => _ids.removeWhere((_, v) => v == id);
}
