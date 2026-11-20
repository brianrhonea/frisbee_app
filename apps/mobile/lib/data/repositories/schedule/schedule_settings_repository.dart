import '../../services/shared_preferences_service.dart';

/// How the Schedule tab was last shown on this device: `week` or `month`
/// (ScheduleView's names). Kept on the device only, as the website keeps
/// its choice in the browser.
abstract class ScheduleSettingsRepository {
  /// The saved view's name; null when none was saved.
  Future<String?> view();

  Future<void> saveView(String view);
}

/// Keeps the choice in memory, until the app restarts. The default where
/// no device storage is given (tests).
class ScheduleSettingsRepositoryMemory implements ScheduleSettingsRepository {
  String? _view;

  @override
  Future<String?> view() async => _view;

  @override
  Future<void> saveView(String view) async => _view = view;
}

/// Keeps the choice in shared preferences. Storage errors fall back to the
/// default view rather than failing the tab.
class ScheduleSettingsRepositoryPrefs implements ScheduleSettingsRepository {
  ScheduleSettingsRepositoryPrefs([SharedPreferencesService Function()? prefs])
    : _make = prefs ?? SharedPreferencesService.new;

  final SharedPreferencesService Function() _make;
  SharedPreferencesService? _prefs;
  final _memory = ScheduleSettingsRepositoryMemory();

  static const _key = 'schedule.view';

  @override
  Future<String?> view() async {
    final mine = await _memory.view();
    if (mine != null) return mine;
    try {
      return await (_prefs ??= _make()).getString(_key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveView(String view) async {
    await _memory.saveView(view);
    try {
      await (_prefs ??= _make()).setString(_key, view);
    } catch (_) {
      // The default view next time; nothing else depends on it.
    }
  }
}
