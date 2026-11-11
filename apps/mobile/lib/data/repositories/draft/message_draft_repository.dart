import 'dart:async';
import 'dart:convert';

import '../../services/shared_preferences_service.dart';

/// Unsent text in message composers, by thread, so leaving a conversation
/// and coming back doesn't lose what was typed.
abstract class MessageDraftRepository {
  /// What was left in [key]'s composer; empty for nothing.
  String draft(String key);

  /// Remembers [text] for [key]; empty forgets it.
  void save(String key, String text);
}

/// Drafts in memory, kept on the device between runs. They're loaded
/// once at start, which is long done by the time anyone opens a chat.
class MessageDraftRepositoryPrefs implements MessageDraftRepository {
  MessageDraftRepositoryPrefs(this._prefs) {
    unawaited(_load());
  }

  final SharedPreferencesService _prefs;
  final _drafts = <String, String>{};
  Timer? _write;

  static const _key = 'messageDrafts';

  /// Drafts kept, newest last; the oldest go past this.
  static const maxDrafts = 50;

  Future<void> _load() async {
    try {
      final raw = await _prefs.getString(_key);
      if (raw == null) return;
      final map = jsonDecode(raw);
      if (map is! Map) return;
      for (final e in map.entries) {
        // Anything typed since start wins over what was stored.
        if (e.value is String) _drafts.putIfAbsent('${e.key}', () => e.value);
      }
    } on Object {
      // A bad entry just means no drafts.
    }
  }

  @override
  String draft(String key) => _drafts[key] ?? '';

  @override
  void save(String key, String text) {
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
    _write = Timer(const Duration(milliseconds: 500), () {
      unawaited(
        _prefs.setString(_key, jsonEncode(_drafts)).catchError((Object _) {}),
      );
    });
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
