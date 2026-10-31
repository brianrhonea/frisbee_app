import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/services/meeting_call.dart';
import '../../chat/widgets/message_thread_view.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../videos/widgets/synced_video_player.dart';
import '../view_models/meeting_room_viewmodel.dart';
import '../view_models/watch_together_viewmodel.dart';
import 'meeting_room_widgets.dart';
import 'watch_together_view.dart';

/// The call: everyone's camera or photo, a video watched together or a
/// shared screen when there is one, the controls, and the meeting chat.
class MeetingCallView extends StatefulWidget {
  const MeetingCallView({
    super.key,
    required this.viewModel,
    this.videoPlayer = syncedVideoPlayer,
  });

  final MeetingRoomViewModel viewModel;
  final SyncedPlayerBuilder videoPlayer;

  @override
  State<MeetingCallView> createState() => _MeetingCallViewState();
}

class _MeetingCallViewState extends State<MeetingCallView> {
  MeetingRoomViewModel get vm => widget.viewModel;

  /// Wide layouts show the chat beside the call; narrow ones in a sheet.
  bool _chatOpen = false;

  static const _wide = 900.0;

  /// Watch together lives as long as the call, and so does this view.
  late final WatchTogetherViewModel? _watch = vm.watch;

  late final _watchCommands = [
    ?_watch?.show,
    ?_watch?.play,
    ?_watch?.pause,
    ?_watch?.seek,
    ?_watch?.stop,
    ?_watch?.takeControl,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _watchCommands) {
      c.addListener(_onWatchCommand);
    }
  }

  @override
  void dispose() {
    for (final c in _watchCommands) {
      c.removeListener(_onWatchCommand);
    }
    super.dispose();
  }

  void _onWatchCommand() {
    for (final c in _watchCommands) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
    }
  }

  Future<void> _pickVideo() async {
    final watch = _watch;
    if (watch == null) return;
    final id = await showVideoPicker(context, watch);
    if (id != null) watch.show.execute(id);
  }

  void _setChat(bool open) {
    setState(() => _chatOpen = open);
    vm.chat?.visible = open;
  }

  Future<void> _toggleChat(bool wide) async {
    final chat = vm.chat;
    if (chat == null) return;
    if (wide) return _setChat(!_chatOpen);
    _setChat(true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: _ChatPanel(viewModel: vm),
      ),
    );
    if (mounted) _setChat(false);
  }

  Future<void> _toggleScreenShare() async {
    if (vm.screenSharing) {
      vm.setScreenSharing.execute((on: false, sourceId: null));
      return;
    }
    String? source;
    if (vm.picksScreenSource) {
      source = await vm.pickScreenSource(context);
      if (source == null) return;
    }
    vm.setScreenSharing.execute((on: true, sourceId: source));
  }

  void _showSettings() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: DeviceSettings(viewModel: vm),
    ),
  );

  void _showRequests() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) =>
        SingleChildScrollView(child: JoinRequestList(viewModel: vm)),
  );

  void _showVolume(CallParticipant p) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => _VolumeSheet(viewModel: vm, participant: p),
  );

  Future<void> _leave() async {
    if (!vm.isAdmin) return vm.leave();
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave the meeting?'),
        content: const Text(
          'You can leave and let it go on, or end it for everyone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Leave'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End for everyone'),
          ),
        ],
      ),
    );
    switch (choice) {
      case true:
        if (mounted &&
            await confirmDialog(
              context,
              title: 'End the meeting?',
              message: 'Everyone will be disconnected.',
              confirmLabel: 'End meeting',
              destructive: true,
            )) {
          vm.endMeeting.execute();
        }
      case false:
        await vm.leave();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final wide = c.maxWidth >= _wide;
      final theme = ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Theme.of(context).colorScheme.primary,
      );
      return Theme(
        data: theme,
        child: ListenableBuilder(
          listenable: Listenable.merge([vm, ?vm.chat, ?_watch]),
          builder: (context, _) => Scaffold(
            backgroundColor: const Color(0xFF111316),
            body: SafeArea(
              child: Column(
                children: [
                  _TopBar(viewModel: vm, onRequests: _showRequests),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _Stage(
                            viewModel: vm,
                            onTap: _showVolume,
                            videoPlayer: widget.videoPlayer,
                          ),
                        ),
                        if (wide && _chatOpen)
                          SizedBox(
                            width: 360,
                            child: Material(
                              color: theme.colorScheme.surface,
                              child: _ChatPanel(
                                viewModel: vm,
                                onClose: () => _setChat(false),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _Controls(
                    viewModel: vm,
                    chatOpen: _chatOpen,
                    onChat: () => _toggleChat(wide),
                    onScreenShare: _toggleScreenShare,
                    onWatch: _pickVideo,
                    onSettings: _showSettings,
                    onLeave: _leave,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.viewModel, required this.onRequests});

  final MeetingRoomViewModel viewModel;
  final VoidCallback onRequests;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final waiting = vm.pendingRequests.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 10, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              vm.meeting?.title ?? 'Meeting',
              style: Theme.of(context).textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${vm.participants.length} in call',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (vm.isAdmin && (vm.meeting?.requireApproval ?? false))
            IconButton(
              tooltip: 'Waiting to join',
              onPressed: onRequests,
              icon: CountBadge(
                count: waiting,
                child: const Icon(Icons.how_to_reg_outlined),
              ),
            ),
        ],
      ),
    );
  }
}

/// Everyone's tiles; or the video watched together, or a shared screen,
/// with the tiles in a strip beside it.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.viewModel,
    required this.onTap,
    required this.videoPlayer,
  });

  final MeetingRoomViewModel viewModel;
  final ValueChanged<CallParticipant> onTap;
  final SyncedPlayerBuilder videoPlayer;

  @override
  Widget build(BuildContext context) {
    final people = viewModel.participants;
    final presenter = viewModel.presenter;
    final watch = viewModel.watch;
    Widget tile(CallParticipant p) => ParticipantTile(
      participant: p,
      onTap: p.isLocal ? null : () => onTap(p),
    );

    Widget featured(Widget main) => LayoutBuilder(
      builder: (context, c) {
        final side = c.maxWidth >= 700;
        final strip = ListView(
          scrollDirection: side ? Axis.vertical : Axis.horizontal,
          padding: const EdgeInsets.all(8),
          children: [
            for (final p in people)
              Padding(
                padding: const EdgeInsets.all(4),
                child: SizedBox(
                  width: side ? null : 160,
                  height: side ? 120 : null,
                  child: tile(p),
                ),
              ),
          ],
        );
        return side
            ? Row(
                children: [
                  Expanded(child: main),
                  SizedBox(width: 220, child: strip),
                ],
              )
            : Column(
                children: [
                  Expanded(child: main),
                  SizedBox(height: 110, child: strip),
                ],
              );
      },
    );

    // Watching together beats a shared screen: it's what the room is for.
    if (watch != null && watch.active) {
      return featured(
        Padding(
          padding: const EdgeInsets.all(8),
          child: WatchTogetherStage(viewModel: watch, player: videoPlayer),
        ),
      );
    }

    if (presenter != null) {
      return featured(
        Padding(
          padding: const EdgeInsets.all(8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  presenter.screen!.view(cover: false),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: _NameTag(
                      text: presenter.isLocal
                          ? 'You are presenting'
                          : '${presenter.name} is presenting',
                      icon: Icons.screen_share_outlined,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        const gap = 8.0;
        final n = math.max(people.length, 1);
        // Columns that make tiles as large as possible at 16:9.
        var best = 1;
        var bestWidth = 0.0;
        for (var cols = 1; cols <= n; cols++) {
          final rows = (n / cols).ceil();
          final w = math.min(
            (c.maxWidth - gap * (cols + 1)) / cols,
            ((c.maxHeight - gap * (rows + 1)) / rows) * 16 / 9,
          );
          if (w > bestWidth) {
            bestWidth = w;
            best = cols;
          }
        }
        final width = math.max(bestWidth, 160.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(gap),
          child: SizedBox(
            width: c.maxWidth - gap * 2,
            child: Wrap(
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final p in people)
                  SizedBox(
                    width: best == 1 ? math.min(width, c.maxWidth) : width,
                    height: width * 9 / 16,
                    child: tile(p),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One person: their camera, or their photo while it's off.
class ParticipantTile extends StatelessWidget {
  const ParticipantTile({super.key, required this.participant, this.onTap});

  final CallParticipant participant;

  /// Opens their volume; null for the user's own tile.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = participant;
    final camera = p.camera;
    return Material(
      color: const Color(0xFF23262B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: p.isSpeaking
            ? const BorderSide(color: Colors.greenAccent, width: 3)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (camera != null)
              camera.view(mirror: p.isLocal)
            else
              Center(
                child: LayoutBuilder(
                  builder: (context, c) => MeetingAvatar(
                    name: p.name,
                    photoUrl: p.photoUrl,
                    size: math.min(96, c.biggest.shortestSide * 0.5),
                  ),
                ),
              ),
            Positioned(
              left: 8,
              bottom: 8,
              right: 8,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _NameTag(
                  text: p.isLocal ? '${p.name} (you)' : p.name,
                  icon: p.micOn ? null : Icons.mic_off,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NameTag extends StatelessWidget {
  const _NameTag({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon case final icon?) ...[
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.viewModel,
    required this.chatOpen,
    required this.onChat,
    required this.onScreenShare,
    required this.onWatch,
    required this.onSettings,
    required this.onLeave,
  });

  final MeetingRoomViewModel viewModel;
  final bool chatOpen;
  final VoidCallback onChat;
  final VoidCallback onScreenShare;
  final VoidCallback onWatch;
  final VoidCallback onSettings;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          CallToggle(
            on: vm.micOn,
            onIcon: Icons.mic,
            offIcon: Icons.mic_off,
            tooltip: vm.micOn ? 'Mute microphone' : 'Unmute microphone',
            onPressed: vm.toggleMic.execute,
          ),
          CallToggle(
            on: vm.cameraOn,
            onIcon: Icons.videocam,
            offIcon: Icons.videocam_off,
            tooltip: vm.cameraOn ? 'Hide camera' : 'Show camera',
            onPressed: vm.toggleCamera.execute,
          ),
          CallToggle(
            on: !vm.audioMuted,
            onIcon: Icons.volume_up,
            offIcon: Icons.volume_off,
            tooltip: vm.audioMuted ? 'Unmute audio' : 'Mute audio',
            onPressed: vm.toggleAudioMuted,
          ),
          if (vm.canShareScreen)
            CallToggle(
              on: vm.screenSharing,
              highlightOn: true,
              onIcon: Icons.stop_screen_share_outlined,
              offIcon: Icons.screen_share_outlined,
              tooltip: vm.screenSharing ? 'Stop sharing' : 'Share screen',
              onPressed: vm.setScreenSharing.running ? null : onScreenShare,
            ),
          if (vm.isAdmin && vm.watch != null)
            CallToggle(
              on: vm.watch!.active,
              highlightOn: true,
              onIcon: Icons.video_library,
              offIcon: Icons.video_library_outlined,
              tooltip: vm.watch!.active
                  ? 'Watch a different video'
                  : 'Watch a video together',
              onPressed: onWatch,
            ),
          CallToggle(
            on: chatOpen,
            highlightOn: true,
            onIcon: Icons.chat,
            offIcon: Icons.chat_bubble_outline,
            tooltip: 'Chat',
            badge: vm.chat?.unread ?? 0,
            onPressed: onChat,
          ),
          CallToggle(
            on: false,
            onIcon: Icons.settings,
            offIcon: Icons.settings_outlined,
            tooltip: 'Audio and video settings',
            onPressed: onSettings,
          ),
          Tooltip(
            message: 'Leave',
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                minimumSize: const Size(72, 48),
              ),
              onPressed: onLeave,
              child: const Icon(Icons.call_end),
            ),
          ),
        ],
      ),
    );
  }
}

/// A round call button. Off is shown in red for the mic and camera, so
/// it's clear at a glance; [highlightOn] instead lights up when on.
class CallToggle extends StatelessWidget {
  const CallToggle({
    super.key,
    required this.on,
    required this.onIcon,
    required this.offIcon,
    required this.tooltip,
    required this.onPressed,
    this.highlightOn = false,
    this.badge = 0,
  });

  final bool on;
  final IconData onIcon;
  final IconData offIcon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool highlightOn;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color background;
    final Color foreground;
    if (highlightOn) {
      background = on ? scheme.primary : Colors.white24;
      foreground = on ? scheme.onPrimary : Colors.white;
    } else {
      background = on ? Colors.white24 : Colors.red.shade600;
      foreground = Colors.white;
    }
    return IconButton.filled(
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        minimumSize: const Size.square(48),
      ),
      onPressed: onPressed,
      icon: CountBadge(count: badge, child: Icon(on ? onIcon : offIcon)),
    );
  }
}

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({required this.viewModel, this.onClose});

  final MeetingRoomViewModel viewModel;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final chat = viewModel.chat;
    return Column(
      children: [
        ListTile(
          title: Text(
            'Meeting chat',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          trailing: onClose == null
              ? null
              : IconButton(
                  tooltip: 'Close chat',
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
        ),
        const Divider(height: 1),
        Expanded(
          child: chat == null
              ? const SizedBox.shrink()
              : MessageThreadView(
                  viewModel: chat,
                  emptyMessage: 'Type here instead of unmuting.',
                  readOnlyNotice: '',
                ),
        ),
      ],
    );
  }
}

/// How loud one person is, for this user only.
class _VolumeSheet extends StatelessWidget {
  const _VolumeSheet({required this.viewModel, required this.participant});

  final MeetingRoomViewModel viewModel;
  final CallParticipant participant;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final vm = viewModel;
      final p = participant;
      final volume = vm.volumeOf(p.uid);
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                MeetingAvatar(name: p.name, photoUrl: p.photoUrl, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(p.name, style: theme.textTheme.titleMedium),
                ),
                Text('${(volume * 100).round()}%'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  tooltip: volume == 0 ? 'Unmute for me' : 'Mute for me',
                  onPressed: () {
                    vm.setVolumeOf(p.uid, volume == 0 ? 1 : 0);
                    vm.saveVolumes();
                  },
                  icon: Icon(
                    volume == 0 ? Icons.volume_off : Icons.volume_down,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: volume,
                    max: 2,
                    divisions: 40,
                    label: '${(volume * 100).round()}%',
                    onChanged: (v) => vm.setVolumeOf(p.uid, v),
                    onChangeEnd: (_) => vm.saveVolumes(),
                  ),
                ),
                const Icon(Icons.volume_up),
              ],
            ),
            Text(
              'Only changes how loud ${p.name} is for you.',
              style: theme.textTheme.bodySmall,
            ),
            if (volume != 1)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    vm.setVolumeOf(p.uid, 1);
                    vm.saveVolumes();
                  },
                  child: const Text('Reset'),
                ),
              ),
          ],
        ),
      );
    },
  );
}
