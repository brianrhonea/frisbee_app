import 'package:shared_preferences/shared_preferences.dart';

/// Small key/value settings stored on the device.
class SharedPreferencesService {
  SharedPreferencesService({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  Future<String?> getString(String key) => _prefs.getString(key);

  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);
}
