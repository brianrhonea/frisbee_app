// Reads and writes the shared example vectors in packages/shared/fixtures,
// which packages/shared's TypeScript tests check too, so the app and the
// API/website ports give the same results for the same inputs.
//
// The app's implementation is the reference: these tests compute the
// expected outputs with it. After changing one of the ported pieces of
// logic, refresh the files and run the TypeScript tests (pnpm test):
//   flutter test test/shared_fixtures --dart-define=UPDATE_FIXTURES=true
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const updateFixtures = bool.fromEnvironment('UPDATE_FIXTURES');
const _fixtures = '../../packages/shared/fixtures';

/// [v] as plain JSON values: dates as local ISO strings (no offset, so
/// both sides read them as the same wall-clock time), enums by name.
Object? jsonable(Object? v) => switch (v) {
  null || bool() || String() => v,
  // Whole doubles stay doubles in Dart but are plain numbers in JSON.
  double d when d == d.roundToDouble() && d.isFinite => d.toInt(),
  num() => v,
  DateTime d => d.toIso8601String(),
  Enum e => e.name,
  Map m => {for (final e in m.entries) '${e.key}': jsonable(e.value)},
  Iterable l => [for (final x in l) jsonable(x)],
  (Object? a, Object? b) => [jsonable(a), jsonable(b)],
  _ => throw ArgumentError('Not JSON: $v (${v.runtimeType})'),
};

/// Checks [cases] against `fixtures/<path>`, or writes them there with
/// `--dart-define=UPDATE_FIXTURES=true`.
void checkFixture(String path, String about, List<Map<String, Object?>> cases) {
  final file = File('$_fixtures/$path');
  final doc = jsonable({'about': about, 'cases': cases});
  if (updateFixtures) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(doc)}\n',
    );
    return;
  }
  expect(
    file.existsSync(),
    isTrue,
    reason: '$path is missing; run with --dart-define=UPDATE_FIXTURES=true',
  );
  expect(
    jsonDecode(file.readAsStringSync()),
    jsonDecode(jsonEncode(doc)),
    reason:
        '$path is out of date; refresh it with '
        '--dart-define=UPDATE_FIXTURES=true and rerun pnpm test',
  );
}

/// A local date from a fixture string.
DateTime date(String s) => DateTime.parse(s);
