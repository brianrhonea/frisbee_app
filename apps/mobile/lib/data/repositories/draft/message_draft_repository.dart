import 'dart:async';
import 'dart:convert';

import '../../services/shared_preferences_service.dart';
import '../auth/auth_repository.dart';

/// Unsent text in message composers, by thread, so leaving a conversation
/// and coming back doesn't lose what was typed. Drafts belong to whoever
/// is signed in, and are forgotten when they sign out.
abstract class MessageDraftRepository {
  /// What the signed-in user left in [key]'s composer; empty for nothing.
  String draft(String key);

  /// Remembers [text] for [key]; empty forgets it.
  void save(String key, String text);
}

/// Drafts in memory, kept on the device between runs under the signed-in
/// user's own key (`messageDrafts_<uid>`, as the website keeps them). They
/// load when that user signs in, which is long done by the time anyone
/// opens a chat. Signing out drops them from memory and the device, so the
/// next person on this phone never sees them.
class MessageDraftRepositoryPrefs implements MessageDraftRepository {
  MessageDraftRepositoryPrefs(
    this._prefs, {
    required AuthRepository auth,
    Duration writeDelay = const Duration(milliseconds: 500),
  }) : _auth = auth,
       _writeDelay = writeDelay {
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  final SharedPreferencesService _prefs;
  final AuthRepository _auth;
  final Duration _writeDelay;
  final _drafts = <String, String>{};
  String? _uid;
  Timer? _write;

  /// Where [uid]'s drafts are kept (messageDraftsKey in packages/shared).
  static String keyFor(String uid) => 'messageDrafts_$uid';

  /// The key every user's drafts once shared; removed when found.
  static const legacyKey = 'messageDrafts';

  /// Drafts kept, newest last; the oldest go past this.
  static const maxDrafts = 50;

  void _onAuthChanged() {
    final uid = _auth.currentUser?.uid;
    if (uid == _uid) return;
    final previous = _uid;
    _uid = uid;
    // Nothing of the last user's carries over, not even a pending write.
    _write?.cancel();
    _write = null;
    _drafts.clear();
    if (previous != null) {
      unawaited(_prefs.remove(keyFor(previous)).catchError((Object _) {}));
    }
    if (uid != null) unawaited(_load(uid));
  }

  Future<void> _load(String uid) async {
    try {
      // Drafts from before they were kept per user can't be told apart.
      unawaited(_prefs.remove(legacyKey).catchError((Object _) {}));
      final raw = await _prefs.getString(keyFor(uid));
      // Signed out (or someone else signed in) meanwhile: not theirs.
      if (raw == null || _uid != uid) return;
      final map = jsonDecode(raw);
      if (map is! Map) return;
      for (final e in map.entries) {
        // Anything typed since sign-in wins over what was stored.
        if (e.value is String) _drafts.putIfAbsent('${e.key}', () => e.value);
      }
    } on Object {
      // A bad entry just means no drafts.
    }
  }

  @override
  String draft(String key) => _uid == null ? '' : _drafts[key] ?? '';

  @override
  void save(String key, String text) {
    final uid = _uid;
    if (uid == null) return;
    if (text.trim().isEmpty) {
      if (_drafts.remove(key) == null) return;
    } else {
      // Re-inserted at the end, so the map runs oldest to newest.
      _drafts
        ..remove(key)
        ..[key] = text;
      while (_drafts.length > maxDrafts) {
        _drafts.remove(_drafts.keys.first);
      }
    }
    // Typing saves a lot; write once it settles.
    _write?.cancel();
    _write = Timer(_writeDelay, () {
      unawaited(
        _prefs
            .setString(keyFor(uid), jsonEncode(_drafts))
            .catchError((Object _) {}),
      );
    });
  }

  /// Stops following sign-ins and drops any pending write.
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _write?.cancel();
  }
}

/// Drafts for this run only (tests, and where storage isn't wanted).
class MessageDraftRepositoryMemory implements MessageDraftRepository {
  final drafts = <String, String>{};

  @override
  String draft(String key) => drafts[key] ?? '';

  @override
  void save(String key, String text) {
    if (text.trim().isEmpty) {
      drafts.remove(key);
    } else {
      drafts[key] = text;
    }
  }
}
