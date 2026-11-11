import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/ui/core/ui/brand.dart';

void main() {
  test('app version matches pubspec.yaml and the changelog', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([0-9.]+)\+',
      multiLine: true,
    ).firstMatch(pubspec)?.group(1);
    expect(version, appVersion);

    final changelog = File('docs/CHANGELOG.md').readAsStringSync();
    expect(changelog, contains('## $appVersion'));
  });
}
