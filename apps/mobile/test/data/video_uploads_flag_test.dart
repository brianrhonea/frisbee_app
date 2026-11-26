// #13: video upload follows meta/flags.videoUploads and fails closed.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/services/feature_flags.dart';
import 'package:frisbee_app/data/services/file_picker_service.dart';

void main() {
  test('the flag defaults to closed', () {
    expect(FeatureFlags.defaults['videoUploads'], isFalse);
    expect(FeatureFlags.fixed(const {}).videoUploads, isFalse);
  });

  test('only an explicit true opens it', () {
    expect(
      FeatureFlags.fixed(const {'videoUploads': true}).videoUploads,
      isTrue,
    );
    expect(
      FeatureFlags.fixed(const {'videoUploads': false}).videoUploads,
      isFalse,
    );
  });

  test('the other kill switches are untouched', () {
    final f = FeatureFlags.fixed(const {'videoUploads': true});
    expect(f.compressImages, isTrue);
    expect(f.useApiTeams, isTrue);
    expect(f.useApiSearch, isFalse);
  });

  test('FilePickerService follows the flag, closed without flags', () {
    expect(FilePickerService().videoUploads, isFalse);
    expect(
      FilePickerService(
        flags: FeatureFlags.fixed(const {'videoUploads': true}),
      ).videoUploads,
      isTrue,
    );
    expect(
      FilePickerService(
        flags: FeatureFlags.fixed(const {'videoUploads': false}),
      ).videoUploads,
      isFalse,
    );
  });
}
