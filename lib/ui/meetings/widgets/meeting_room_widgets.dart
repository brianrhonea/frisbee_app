import 'package:flutter/material.dart';

import '../../../data/services/meeting_call.dart';
import '../../core/ui/layout.dart' show PersonAvatar;
import '../view_models/meeting_room_viewmodel.dart';

/// A person's photo or initials at [size].
class MeetingAvatar extends StatelessWidget {
  const MeetingAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.size = 72,
  });

  final String name;
  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: FittedBox(
      child: PersonAvatar(name: name, photoUrl: photoUrl),
    ),
  );
}

/// Mic, camera and speaker pickers plus the volume slider. Used in the
/// lobby and from the call's settings.
class DeviceSettings extends StatelessWidget {
  const DeviceSettings({super.key, required this.viewModel});

  final MeetingRoomViewModel viewModel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final vm = viewModel;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DevicePicker(
            viewModel: vm,
            kind: MediaDeviceKind.audioInput,
            label: 'Microphone',
            icon: Icons.mic_none,
          ),
          const SizedBox(height: 12),
          _DevicePicker(
            viewModel: vm,
            kind: MediaDeviceKind.videoInput,
            label: 'Camera',
            icon: Icons.videocam_outlined,
          ),
          if (vm.canPickSpeaker) ...[
            const SizedBox(height: 12),
            _DevicePicker(
              viewModel: vm,
              kind: MediaDeviceKind.audioOutput,
              label: 'Speaker',
              icon: Icons.volume_up_outlined,
            ),
          ],
          const SizedBox(height: 16),
          Text('Meeting volume', style: Theme.of(context).textTheme.labelLarge),
          Row(
            children: [
              const Icon(Icons.volume_down_outlined),
              Expanded(
                child: Slider(
                  value: vm.outputVolume,
                  label: '${(vm.outputVolume * 100).round()}%',
                  divisions: 20,
                  onChanged: vm.setOutputVolume,
                  onChangeEnd: (_) => vm.saveVolumes(),
                ),
              ),
              const Icon(Icons.volume_up_outlined),
            ],
          ),
          Text(
            'Only changes what you hear. Tap someone in the meeting to set '
            'how loud they are for you.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    },
  );
}

class _DevicePicker extends StatelessWidget {
  const _DevicePicker({
    required this.viewModel,
    required this.kind,
    required this.label,
    required this.icon,
  });

  final MeetingRoomViewModel viewModel;
  final MediaDeviceKind kind;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final devices = viewModel.devicesOf(kind);
    final selected = viewModel.selected(kind);
    return DropdownButtonFormField<MediaDeviceInfo?>(
      // Rebuilt when the device list changes so the selection stays valid.
      key: ValueKey('$kind-${devices.length}-${selected?.id}'),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('System default')),
        for (final d in devices)
          DropdownMenuItem(
            value: d,
            child: Text(d.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (d) {
        if (d != null) viewModel.useDevice.execute(d);
      },
    );
  }
}

/// Admins: people waiting to be let in.
class JoinRequestList extends StatelessWidget {
  const JoinRequestList({super.key, required this.viewModel});

  final MeetingRoomViewModel viewModel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([viewModel, viewModel.decide]),
    builder: (context, _) {
      final requests = viewModel.pendingRequests;
      if (requests.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Nobody is waiting.', textAlign: TextAlign.center),
        );
      }
      final busy = viewModel.decide.running;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final r in requests)
            ListTile(
              leading: PersonAvatar(name: r.name),
              title: Text(r.name.isEmpty ? 'Member' : r.name),
              subtitle: const Text('Wants to join'),
              trailing: Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => viewModel.decide.execute((
                            uid: r.uid,
                            admit: false,
                          )),
                    child: const Text('Deny'),
                  ),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => viewModel.decide.execute((
                            uid: r.uid,
                            admit: true,
                          )),
                    child: const Text('Admit'),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

/// A small count on top of [child].
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) => Badge(
    isLabelVisible: count > 0,
    label: Text(count > 99 ? '99+' : '$count'),
    child: child,
  );
}
