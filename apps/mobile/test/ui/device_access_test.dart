import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/services/device_permissions.dart';
import 'package:frisbee_app/ui/settings/view_models/device_access_viewmodel.dart';
import 'package:frisbee_app/ui/settings/widgets/device_access_group.dart';

class _FakePermissions implements DevicePermissions {
  _FakePermissions(this.statuses);

  final Map<DeviceAccess, AccessStatus> statuses;
  var opened = 0;

  @override
  bool get supported => true;

  @override
  Future<AccessStatus> status(DeviceAccess a) async => statuses[a]!;

  @override
  Future<AccessStatus> request(DeviceAccess a) async =>
      statuses[a] = AccessStatus.allowed;

  @override
  Future<bool> openSettings() async {
    opened++;
    return true;
  }
}

void main() {
  testWidgets('shows each permission, asks for unasked ones, and opens '
      "the phone's settings", (tester) async {
    final perms = _FakePermissions({
      DeviceAccess.photos: AccessStatus.limited,
      DeviceAccess.camera: AccessStatus.notAsked,
      DeviceAccess.microphone: AccessStatus.denied,
    });
    final vm = DeviceAccessViewModel(permissions: perms);
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: DeviceAccessGroup(viewModel: vm)),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Selected photos only'), findsOneWidget);
    expect(find.textContaining('Not asked yet'), findsOneWidget);
    expect(find.textContaining('Not allowed'), findsOneWidget);
    await tester.tap(find.text('Allow'));
    await tester.pump();
    expect(vm.statusOf(DeviceAccess.camera), AccessStatus.allowed);
    expect(find.text('Allow'), findsNothing);
    await tester.tap(find.text("Open your phone's settings"));
    await tester.pump();
    expect(perms.opened, 1);
  });
}
