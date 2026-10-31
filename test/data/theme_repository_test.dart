import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/theme/theme_repository_prefs.dart';
import 'package:frisbee_app/data/services/shared_preferences_service.dart';

class _MemoryPrefs implements SharedPreferencesService {
  final values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async => values[key] = value;
}

void main() {
  test('defaults to following the device', () async {
    final repo = await ThemeRepositoryPrefs.load(_MemoryPrefs());
    expect(repo.themeMode, ThemeMode.system);
  });

  test('saves the choice and loads it next launch', () async {
    final prefs = _MemoryPrefs();
    final repo = await ThemeRepositoryPrefs.load(prefs);
    var notified = 0;
    repo.addListener(() => notified++);

    await repo.setThemeMode(ThemeMode.dark);
    expect(repo.themeMode, ThemeMode.dark);
    expect(notified, 1);

    final reopened = await ThemeRepositoryPrefs.load(prefs);
    expect(reopened.themeMode, ThemeMode.dark);
  });

  test('ignores an unknown saved value', () async {
    final prefs = _MemoryPrefs()..values['themeMode'] = 'neon';
    final repo = await ThemeRepositoryPrefs.load(prefs);
    expect(repo.themeMode, ThemeMode.system);
  });
}
