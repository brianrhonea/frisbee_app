import 'package:flutter/material.dart';

import '../../../data/services/meeting_call.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/status_views.dart';
import '../view_models/voice_channel_viewmodel.dart';

/// A voice channel: join to talk, see who's here and who's speaking.
class VoiceChannelView extends StatefulWidget {
  const VoiceChannelView({super.key, required this.viewModel});

  final VoiceChannelViewModel viewModel;

  @override
  State<VoiceChannelView> createState() => _VoiceChannelViewState();
}

class _VoiceChannelViewState extends State<VoiceChannelView> {
  VoiceChannelViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.join.addListener(_onCommand);
    vm.toggleMic.addListener(_onCommand);
  }

  @override
  void dispose() {
    vm.join.removeListener(_onCommand);
    vm.toggleMic.removeListener(_onCommand);
    super.dispose();
  }

  void _onCommand() {
    for (final c in [vm.join, vm.toggleMic]) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) {
      final c = AppColors.of(context);
      if (!vm.loaded) return const LoadingState();
      final room = vm.room;
      if (room == null || !vm.access.canRead) {
        return room == null && vm.error != null
            ? ErrorState(error: vm.error)
            : EmptyState(
                icon: Icons.lock_outline,
                title: room == null
                    ? 'Channel not available'
                    : "You don't have access to this channel",
                message: room == null ? 'It may have been deleted.' : null,
              );
      }
      if (!vm.connected) {
        final elsewhere = vm.elsewhere;
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: c.accentSoft,
                    foregroundColor: c.accentInk,
                    child: const Icon(Icons.volume_up_rounded, size: 44),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    room.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    vm.canSpeak
                        ? 'Drop in any time to talk with the team.'
                        : 'You can listen here, but not talk.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted),
                  ),
                  if (vm.notice case final notice?) ...[
                    const SizedBox(height: 10),
                    Text(
                      notice,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: c.ink2,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  if (vm.connecting)
                    const Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 10),
                        Text('Connecting…'),
                      ],
                    )
                  else
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(200, 48),
                      ),
                      onPressed: vm.join.running ? null : vm.join.execute,
                      icon: const Icon(Icons.headset_mic_rounded),
                      label: const Text('Join voice'),
                    ),
                  if (elsewhere != null && !vm.connecting) ...[
                    const SizedBox(height: 10),
                    Text(
                      'This leaves ${elsewhere.name}'
                      '${elsewhere.teamName.isEmpty ? '' : ' in ${elsewhere.teamName}'}.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: c.muted),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }
      return Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpace.xl),
              child: Center(
                child: Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final p in vm.participants) _ParticipantTile(p: p),
                  ],
                ),
              ),
            ),
          ),
          _CallControls(viewModel: vm),
        ],
      );
    },
  );
}

/// A person in the channel, ringed in turf while they talk.
class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({required this.p});

  final CallParticipant p;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: 180,
      height: 140,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: p.isSpeaking ? c.accent : c.border,
          width: p.isSpeaking ? 2.5 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: p.isSpeaking ? c.accent : Colors.transparent,
                width: 3,
              ),
            ),
            child: PersonAvatar(name: p.name, photoUrl: p.photoUrl, radius: 30),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!p.micOn) ...[
                Icon(
                  Icons.mic_off,
                  size: 16,
                  color: c.muted,
                  semanticLabel: 'Muted',
                ),
                const SizedBox(width: 4),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(
                  p.isLocal ? '${p.name} (you)' : p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CallControls extends StatelessWidget {
  const _CallControls({required this.viewModel});

  final VoiceChannelViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.filledTonal(
            iconSize: 26,
            tooltip: !vm.canSpeak
                ? 'You can only listen here'
                : vm.micOn
                ? 'Mute'
                : 'Unmute',
            style: IconButton.styleFrom(
              fixedSize: const Size(56, 56),
              backgroundColor: vm.micOn ? c.accentSoft : c.field,
              foregroundColor: vm.micOn ? c.accentInk : c.ink,
              side: vm.micOn ? BorderSide(color: c.accent, width: 1.5) : null,
            ),
            icon: Icon(vm.micOn ? Icons.mic : Icons.mic_off),
            onPressed: vm.canSpeak && !vm.toggleMic.running
                ? vm.toggleMic.execute
                : null,
          ),
          const SizedBox(width: 20),
          // Leaving, but in ink rather than red: red is kept for live
          // games.
          IconButton.filled(
            iconSize: 26,
            tooltip: 'Disconnect',
            style: IconButton.styleFrom(
              fixedSize: const Size(56, 56),
              backgroundColor: c.ink2,
              foregroundColor: c.card,
            ),
            icon: const Icon(Icons.call_end),
            onPressed: vm.leave.execute,
          ),
        ],
      ),
    );
  }
}
