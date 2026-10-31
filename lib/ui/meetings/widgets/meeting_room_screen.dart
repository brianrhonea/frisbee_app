import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../routing/routes.dart';
import '../../../utils/command.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/meeting_room_viewmodel.dart';
import 'meeting_call_view.dart';
import 'meeting_detail_screen.dart' show MeetingStatusBadge;
import 'meeting_room_widgets.dart';

/// The meeting room: a lobby to pick devices and get in, then the call.
class MeetingRoomScreen extends StatefulWidget {
  const MeetingRoomScreen({super.key, required this.viewModel});

  final MeetingRoomViewModel viewModel;

  @override
  State<MeetingRoomScreen> createState() => _MeetingRoomScreenState();
}

class _MeetingRoomScreenState extends State<MeetingRoomScreen> {
  MeetingRoomViewModel get vm => widget.viewModel;

  late final List<Command<Object?>> _commands = [
    vm.start,
    vm.join,
    vm.askToJoin,
    vm.cancelAsk,
    vm.decide,
    vm.endMeeting,
    vm.toggleMic,
    vm.toggleCamera,
    vm.setScreenSharing,
    vm.useDevice,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _commands) {
      c.addListener(_onCommand);
    }
  }

  @override
  void dispose() {
    for (final c in _commands) {
      c.removeListener(_onCommand);
    }
    super.dispose();
  }

  void _onCommand() {
    for (final c in _commands) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
    }
  }

  void _exit() => context.canPop()
      ? context.pop()
      : context.go(Routes.meeting(vm.teamId, vm.meetingId));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) => switch (vm.stage) {
      RoomStage.inCall => MeetingCallView(viewModel: vm),
      RoomStage.left => _LeftView(viewModel: vm, onExit: _exit),
      RoomStage.lobby || RoomStage.joining => _Lobby(viewModel: vm),
    },
  );
}

class _Lobby extends StatelessWidget {
  const _Lobby({required this.viewModel});

  final MeetingRoomViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final m = vm.meeting;
    final state = vm.lobbyState;
    final theme = Theme.of(context);
    final preview = _Preview(viewModel: vm);
    final panel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (m != null) ...[
          Row(
            children: [
              Expanded(
                child: Text(m.title, style: theme.textTheme.headlineSmall),
              ),
              if (m.isLive || m.isEnded) MeetingStatusBadge(meeting: m),
            ],
          ),
          Text(
            DateFormat.yMMMEd().add_jm().format(m.startsAt),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
        ],
        _GetIn(viewModel: vm, state: state),
        if (vm.isAdmin && (m?.isLive ?? false) && vm.pendingRequests.isNotEmpty)
          Card.outlined(
            margin: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    'Waiting to join',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                JoinRequestList(viewModel: vm),
              ],
            ),
          ),
        const Divider(height: 32),
        DeviceSettings(viewModel: vm),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        leading: backOr(context, Routes.meeting(vm.teamId, vm.meetingId)),
        title: const Text('Meeting room'),
      ),
      body: state == LobbyState.loading
          ? const LoadingView()
          : LayoutBuilder(
              builder: (context, c) {
                if (c.maxWidth >= 840) {
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: preview,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: panel,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [preview, const SizedBox(height: 16), panel],
                );
              },
            ),
    );
  }
}

/// The user's camera (or photo) with the mic and camera toggles.
class _Preview extends StatelessWidget {
  const _Preview({required this.viewModel});

  final MeetingRoomViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final video = vm.preview;
    final notice = vm.mediaNotice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ColoredBox(
              color: Colors.black87,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (video != null)
                    video.view(mirror: true)
                  else
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MeetingAvatar(
                            name: vm.myName,
                            photoUrl: vm.myPhotoUrl,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Camera is off',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CallToggle(
                          on: vm.micOn,
                          onIcon: Icons.mic,
                          offIcon: Icons.mic_off,
                          tooltip: vm.micOn ? 'Mute' : 'Unmute',
                          onPressed: vm.toggleMic.execute,
                        ),
                        const SizedBox(width: 12),
                        CallToggle(
                          on: vm.cameraOn,
                          onIcon: Icons.videocam,
                          offIcon: Icons.videocam_off,
                          tooltip: vm.cameraOn
                              ? 'Turn camera off'
                              : 'Turn camera on',
                          onPressed: vm.toggleCamera.execute,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(notice)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Start, join, ask to join, or wait: whatever the lobby allows now.
class _GetIn extends StatelessWidget {
  const _GetIn({required this.viewModel, required this.state});

  final MeetingRoomViewModel viewModel;
  final LobbyState state;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final theme = Theme.of(context);
    final joining = vm.stage == RoomStage.joining || vm.join.running;
    Widget button(String label, IconData icon, VoidCallback? onPressed) =>
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: joining ? null : onPressed,
          icon: joining
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon),
          label: Text(joining ? 'Joining…' : label),
        );
    Widget note(String text) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
    );

    switch (state) {
      case LobbyState.loading:
        return const Center(child: CircularProgressIndicator());
      case LobbyState.unavailable:
        return const EmptyView(
          icon: Icons.videocam_off_outlined,
          title: "You can't join this meeting",
          message: "It may have been deleted, or you weren't invited.",
        );
      case LobbyState.ended:
        return const EmptyView(
          icon: Icons.check_circle_outline,
          title: 'This meeting has ended',
        );
      case LobbyState.canStart:
        final early = vm.isEarly;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            button(
              early ? 'Start meeting early' : 'Start meeting',
              Icons.play_arrow,
              vm.start.running ? null : vm.start.execute,
            ),
            note('Invitees who are attending get notified when you start.'),
          ],
        );
      case LobbyState.waitingToStart:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ListTile(
              leading: Icon(Icons.hourglass_top),
              title: Text('Waiting for an admin to start the meeting'),
            ),
            SwitchListTile(
              title: const Text('Join as soon as it starts'),
              value: vm.wantsIn,
              onChanged: vm.setWantsIn,
            ),
          ],
        );
      case LobbyState.canJoin:
        return button('Join meeting', Icons.login, vm.join.execute);
      case LobbyState.canAsk:
        final denied = vm.myRequest?.isDenied ?? false;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (denied)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  "An admin didn't let you in.",
                  style: TextStyle(color: theme.colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            button(
              denied ? 'Ask again' : 'Ask to join',
              Icons.front_hand_outlined,
              vm.askToJoin.running ? null : vm.askToJoin.execute,
            ),
            note('An admin needs to let you in to this meeting.'),
          ],
        );
      case LobbyState.waitingForApproval:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ListTile(
              leading: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text('Waiting for an admin to let you in'),
              subtitle: Text("You'll join automatically."),
            ),
            TextButton(
              onPressed: vm.cancelAsk.running ? null : vm.cancelAsk.execute,
              child: const Text('Cancel request'),
            ),
          ],
        );
    }
  }
}

class _LeftView extends StatelessWidget {
  const _LeftView({required this.viewModel, required this.onExit});

  final MeetingRoomViewModel viewModel;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final ended = vm.meeting?.isEnded ?? true;
    return Scaffold(
      appBar: AppBar(title: const Text('Meeting room')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EmptyView(
                icon: ended ? Icons.check_circle_outline : Icons.logout,
                title: vm.endNotice ?? 'You left the meeting',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  if (!ended)
                    FilledButton.icon(
                      onPressed: vm.backToLobby,
                      icon: const Icon(Icons.login),
                      label: const Text('Rejoin'),
                    ),
                  OutlinedButton(
                    onPressed: onExit,
                    child: const Text('Back to meeting'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
