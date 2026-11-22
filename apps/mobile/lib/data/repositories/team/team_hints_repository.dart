import '../../services/shared_preferences_service.dart';

/// One-time hints on a team's page that the user dismissed, kept on this
/// device only (a lost dismissal just shows the hint again).
abstract class TeamHintsRepository {
  /// Whether the user dismissed the "turn on sections" hint for [teamId].
  Future<bool> sectionsHintDismissed(String teamId);

  Future<void> dismissSectionsHint(String teamId);
}

/// Keeps dismissals in memory: they last until the app restarts. The
/// default where no device storage is given (tests).
class TeamHintsRepositoryMemory implements TeamHintsRepository {
  final _dismissed = <String>{};

  @override
  Future<bool> sectionsHintDismissed(String teamId) async =>
      _dismissed.contains(teamId);

  @override
  Future<void> dismissSectionsHint(String teamId) async =>
      _dismissed.add(teamId);
}

/// Keeps dismissals in shared preferences. Storage errors count as "not
/// dismissed" rather than failing the page.
class TeamHintsRepositoryPrefs implements TeamHintsRepository {
  TeamHintsRepositoryPrefs([SharedPreferencesService Function()? prefs])
    : _make = prefs ?? SharedPreferencesService.new;

  final SharedPreferencesService Function() _make;
  SharedPreferencesService? _prefs;
  final _memory = TeamHintsRepositoryMemory();

  static String _key(String teamId) => 'teamHints.sections.$teamId';

  @override
  Future<bool> sectionsHintDismissed(String teamId) async {
    if (await _memory.sectionsHintDismissed(teamId)) return true;
    try {
      return await (_prefs ??= _make()).getString(_key(teamId)) != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> dismissSectionsHint(String teamId) async {
    await _memory.dismissSectionsHint(teamId);
    try {
      await (_prefs ??= _make()).setString(_key(teamId), '1');
    } catch (_) {
      // Shown again next time; nothing else depends on it.
    }
  }
}
