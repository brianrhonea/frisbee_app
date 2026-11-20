import 'package:flutter/material.dart';

import '../../../data/services/device_permissions.dart';
import '../../core/themes/theme.dart';
import '../view_models/device_access_viewmodel.dart';
import 'settings_widgets.dart';

/// Photos, camera and microphone access on this phone. Nothing on desktop
/// and web, which use the system file dialogs.
class DeviceAccessGroup extends StatelessWidget {
  const DeviceAccessGroup({super.key, required this.viewModel});

  final DeviceAccessViewModel viewModel;

  static IconData _icon(DeviceAccess a) => switch (a) {
    DeviceAccess.photos => Icons.photo_library_outlined,
    DeviceAccess.camera => Icons.photo_camera_outlined,
    DeviceAccess.microphone => Icons.mic_none,
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final vm = viewModel;
      if (!vm.supported) return const SizedBox.shrink();
      return SettingsGroup(
        title: 'Photos, camera & microphone',
        footer:
            'Stall 10 asks the first time it needs each one. To change one '
            "you've already answered, open your phone's settings.",
        children: [
          for (final a in DeviceAccess.values)
            ListTile(
              leading: SettingsIcon(_icon(a)),
              title: Text(a.label),
              subtitle: Text(
                '${vm.statusOf(a)?.label ?? 'Checking…'} · ${a.purpose}',
              ),
              trailing: vm.statusOf(a) == AccessStatus.notAsked
                  ? OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.of(context).accent,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => vm.ask.execute(a),
                      child: const Text('Allow'),
                    )
                  : null,
            ),
          ListTile(
            leading: const SettingsIcon(Icons.settings_outlined),
            title: const Text("Open your phone's settings"),
            trailing: Icon(
              Icons.open_in_new,
              size: 18,
              color: AppColors.of(context).muted,
            ),
            onTap: vm.openSettings.execute,
          ),
        ],
      );
    },
  );
}
