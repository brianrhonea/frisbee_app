// "Download your data" (redesign F14): Settings › Account fetches the
// API's JSON file and hands it to the share sheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/domain/models/data_export.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/profile/view_models/profile_viewmodel.dart';
import 'package:frisbee_app/ui/settings/widgets/download_data_group.dart';
import 'package:frisbee_app/ui/settings/widgets/settings_screen.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';

void main() {
  late FakeAuthRepository auth;
  late ProfileViewModel vm;
  final now = DateTime.utc(2026, 11, 20, 12);

  setUp(() {
    auth = FakeAuthRepository(user: testUser);
    vm = ProfileViewModel(
      authRepository: auth,
      themeRepository: FakeThemeRepository(),
      notificationRepository: FakeNotificationRepository(),
      directMessageRepository: FakeDirectMessageRepository(),
      clock: () => now,
    );
  });

  test('the file is named by the day, as the API names it', () {
    expect(DataExportFile.fileName(now), 'stall10-data-2026-11-20.json');
  });

  test('the command fetches the JSON and names the file', () async {
    await vm.downloadData.execute();
    final file = (vm.downloadData.result as Ok<DataExportFile>).value;
    expect(file.name, 'stall10-data-2026-11-20.json');
    expect(file.json, contains('stall10-data-export'));
    expect(auth.exports, 1);
  });

  Future<List<DataExportFile>> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shared = <DataExportFile>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AccountSettingsScreen(
          viewModel: vm,
          shareFile: (_, file) async => shared.add(file),
        ),
      ),
    );
    return shared;
  }

  testWidgets('Account › Your data shares the downloaded file', (tester) async {
    final shared = await pump(tester);
    expect(find.text('YOUR DATA'), findsOneWidget);
    expect(find.text(downloadDataDescription), findsOneWidget);
    await tester.tap(find.text('Download your data'));
    await tester.pumpAndSettle();
    expect(shared.map((f) => f.name), ['stall10-data-2026-11-20.json']);
    expect(shared.single.json, contains('stall10-data-export'));
  });

  testWidgets("the API's answer shows when it's too soon", (tester) async {
    auth.exportResult = const ApiException(
      'resource_exhausted',
      'You can download your data once every 10 minutes. '
          'Try again in 6 minutes.',
    );
    final shared = await pump(tester);
    await tester.tap(find.text('Download your data'));
    await tester.pumpAndSettle();
    expect(shared, isEmpty);
    expect(find.textContaining('Try again in 6 minutes.'), findsOneWidget);
  });
}
