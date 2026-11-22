import 'dart:convert';

import '../../services/shared_preferences_service.dart';

/// Which Learn lessons the user has read, kept on this device only (as
/// the website keeps them in localStorage): losing them just shows the
/// lessons unread again. Not synced between devices.
abstract class LearnProgressRepository {
  /// The ids of the lessons read (learnSections' ids).
  Future<Set<String>> readLessons();

  /// Replaces the lessons read with [ids].
  Future<void> saveReadLessons(Set<String> ids);
}

/// Keeps them in memory: they last until the app restarts. The default
/// where no device storage is given (tests).
class LearnProgressRepositoryMemory implements LearnProgressRepository {
  LearnProgressRepositoryMemory([Set<String>? read]) : _read = {...?read};

  Set<String> _read;

  @override
  Future<Set<String>> readLessons() async => {..._read};

  @override
  Future<void> saveReadLessons(Set<String> ids) async => _read = {...ids};
}

/// Keeps them in shared preferences under `learn.read` (learnReadKey), as
/// a JSON list. Storage errors read as "nothing read" rather than failing
/// the page.
class LearnProgressRepositoryPrefs implements LearnProgressRepository {
  LearnProgressRepositoryPrefs([SharedPreferencesService Function()? prefs])
    : _make = prefs ?? SharedPreferencesService.new;

  final SharedPreferencesService Function() _make;
  SharedPreferencesService? _prefs;

  static const key = 'learn.read';

  @override
  Future<Set<String>> readLessons() async {
    try {
      final raw = await (_prefs ??= _make()).getString(key);
      if (raw == null) return {};
      final list = jsonDecode(raw);
      return list is List
          ? {
              for (final x in list)
                if (x is String) x,
            }
          : {};
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> saveReadLessons(Set<String> ids) async {
    try {
      final prefs = _prefs ??= _make();
      if (ids.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, jsonEncode(ids.toList()..sort()));
      }
    } catch (_) {
      // Shown unread again next time; nothing else depends on it.
    }
  }
}
