// Mirrors packages/shared/test/meta_flags.test.ts (the contract's vectors).
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/meta_flags.dart';

void main() {
  group('MetaFlags.parse', () {
    test('defaults to no gate and videos off', () {
      expect(MetaFlags.parse(null), MetaFlags.defaults);
      expect(MetaFlags.parse(<String, Object?>{}), const MetaFlags());
      expect(MetaFlags.defaults.videoUploads, isFalse);
      expect(MetaFlags.defaults.minBuildIos, 0);
      expect(MetaFlags.defaults.minBuildAndroid, 0);
    });

    test('reads valid values', () {
      expect(
        MetaFlags.parse({
          'minBuild': {'ios': 120, 'android': 7},
          'videoUploads': true,
        }),
        const MetaFlags(
          minBuildIos: 120,
          minBuildAndroid: 7,
          videoUploads: true,
        ),
      );
    });

    test('ignores malformed values per field', () {
      expect(
        MetaFlags.parse({
          'minBuild': {'ios': '120', 'android': -1},
          'videoUploads': 'true',
        }),
        MetaFlags.defaults,
      );
      expect(
        MetaFlags.parse({'minBuild': 5, 'videoUploads': 1}),
        MetaFlags.defaults,
      );
      final bad = MetaFlags.parse({
        'minBuild': {'ios': 1.5, 'android': double.nan},
      });
      expect([bad.minBuildIos, bad.minBuildAndroid], [0, 0]);
      expect(MetaFlags.parse('x'), MetaFlags.defaults);
    });

    test('a bad field does not spoil a good one', () {
      final f = MetaFlags.parse({
        'minBuild': {'ios': 'x', 'android': 30},
        'videoUploads': true,
      });
      expect([f.minBuildIos, f.minBuildAndroid, f.videoUploads], [0, 30, true]);
    });

    test('a whole number that arrives as a double counts', () {
      expect(
        MetaFlags.parse({
          'minBuild': {'ios': 120.0},
        }).minBuildIos,
        120,
      );
      expect(
        MetaFlags.parse({
          'minBuild': {'ios': double.infinity},
        }).minBuildIos,
        0,
      );
    });

    test('only a literal true opens video uploads', () {
      for (final v in [false, 'true', 1, null, 'yes', const <Object>[]]) {
        expect(MetaFlags.parse({'videoUploads': v}).videoUploads, isFalse);
      }
      expect(MetaFlags.parse({'videoUploads': true}).videoUploads, isTrue);
    });
  });

  group('MetaFlags.isBuildAllowed', () {
    final flags = MetaFlags.parse({
      'minBuild': {'ios': 100, 'android': 0},
    });

    test('gates per platform', () {
      expect(MetaFlags.isBuildAllowed(flags, AppPlatform.ios, 99), isFalse);
      expect(MetaFlags.isBuildAllowed(flags, AppPlatform.ios, 100), isTrue);
      expect(MetaFlags.isBuildAllowed(flags, AppPlatform.android, 1), isTrue);
    });

    test('fails open when the flags can\'t be read', () {
      expect(MetaFlags.isBuildAllowed(null, AppPlatform.ios, 1), isTrue);
    });

    test('0 means no gate', () {
      expect(
        MetaFlags.isBuildAllowed(MetaFlags.defaults, AppPlatform.ios, 0),
        isTrue,
      );
    });
  });
}
