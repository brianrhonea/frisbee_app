import 'package:flutter/material.dart';

import '../../../domain/models/team_video.dart';
import '../../videos/widgets/synced_video_player.dart';
import '../../videos/widgets/youtube_player_view.dart';
import '../view_models/watch_together_viewmodel.dart';

/// The video everyone's watching, with who's presenting, and for the
/// presenter play, pause, a scrubber and Stop. Other admins can take over.
class WatchTogetherStage extends StatelessWidget {
  const WatchTogetherStage({
    super.key,
    required this.viewModel,
    required this.player,
  });

  final WatchTogetherViewModel viewModel;
  final SyncedPlayerBuilder player;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final p = vm.playback!;
    final video = vm.video;
    final presenting = vm.isPresenter
        ? 'You are presenting'
        : '${p.presenterName.isEmpty ? 'An admin' : p.presenterName} is '
              'presenting';
    final Widget screen;
    if (video == null) {
      screen = const _Message("This video isn't available.");
    } else if (!video.isYouTube && vm.fileFailed) {
      screen = const _Message("Couldn't load this video.");
    } else {
      screen = KeyedSubtree(
        // A new video gets a new player, and a new controller.
        key: ValueKey(p.videoId),
        child: player(video, vm.fileUrl, vm.attach),
      );
    }
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  screen,
                  Positioned(
                    left: 8,
                    top: 8,
                    right: 8,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: _Tag(
                        icon: Icons.video_library_outlined,
                        text: [presenting, ?video?.title].join(' · '),
                      ),
                    ),
                  ),
                  if (vm.needsTap)
                    const Positioned(
                      left: 8,
                      bottom: 8,
                      // Taps go through to the player underneath.
                      child: IgnorePointer(
                        child: _Tag(
                          icon: Icons.touch_app_outlined,
                          text: 'Tap the video to start it on this device',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (vm.controlling)
          _Transport(viewModel: vm)
        else if (vm.canControl)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: vm.takeControl.running
                      ? null
                      : vm.takeControl.execute,
                  icon: const Icon(Icons.pan_tool_outlined),
                  label: const Text('Take control'),
                ),
                TextButton.icon(
                  onPressed: vm.stop.running ? null : vm.stop.execute,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop for everyone'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(text, style: const TextStyle(color: Colors.white)),
  );
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.icon});

  final String text;
  final IconData icon;

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
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
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

/// "1:05" or "1:02:05".
String clockOf(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// The presenter's controls. They drive everyone's player.
class _Transport extends StatefulWidget {
  const _Transport({required this.viewModel});

  final WatchTogetherViewModel viewModel;

  @override
  State<_Transport> createState() => _TransportState();
}

class _TransportState extends State<_Transport> {
  /// Where the thumb is while it's dragged; the seek happens on release.
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final playing = vm.playback?.playing ?? false;
    final total = vm.duration;
    final max = (total?.inMilliseconds ?? 0).toDouble();
    final at = _dragging ?? vm.position.inMilliseconds.toDouble();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: playing ? 'Pause for everyone' : 'Play for everyone',
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            onPressed: playing ? vm.pause.execute : vm.play.execute,
          ),
          Text(
            '${clockOf(Duration(milliseconds: at.round()))}'
            '${total == null ? '' : ' / ${clockOf(total)}'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Expanded(
            child: Slider(
              value: max <= 0 ? 0 : at.clamp(0, max),
              max: max <= 0 ? 1 : max,
              onChanged: max <= 0 ? null : (v) => setState(() => _dragging = v),
              onChangeEnd: max <= 0
                  ? null
                  : (v) {
                      setState(() => _dragging = null);
                      vm.seek.execute(Duration(milliseconds: v.round()));
                    },
            ),
          ),
          TextButton.icon(
            onPressed: vm.stop.running ? null : vm.stop.execute,
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}

/// Lets an admin pick one of the team's videos, by folder. Returns its id.
Future<String?> showVideoPicker(
  BuildContext context,
  WatchTogetherViewModel viewModel,
) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * 0.75,
    child: _VideoPicker(viewModel: viewModel),
  ),
);

class _VideoPicker extends StatefulWidget {
  const _VideoPicker({required this.viewModel});

  final WatchTogetherViewModel viewModel;

  @override
  State<_VideoPicker> createState() => _VideoPickerState();
}

class _VideoPickerState extends State<_VideoPicker> {
  /// Null for every video, '' for unsorted, or a folder id.
  String? _folder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.viewModel,
    builder: (context, _) {
      final vm = widget.viewModel;
      final theme = Theme.of(context);
      final folderIds = {for (final f in vm.folders) f.id};
      bool inFolder(TeamVideo v) => switch (_folder) {
        null => true,
        '' => !folderIds.contains(v.folderId),
        final id => v.folderId == id,
      };
      final shown = vm.videos.where(inFolder).toList();
      Widget chip(String? id, String label) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _folder == id,
          onSelected: (_) => setState(() => _folder = id),
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Watch a video together',
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (vm.folders.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  chip(null, 'All'),
                  for (final f in vm.folders) chip(f.id, f.name),
                  chip('', 'Unsorted'),
                ],
              ),
            ),
          Expanded(
            child: vm.videos.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No team videos yet. Add some in the team\'s Videos '
                        'section first.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : shown.isEmpty
                ? const Center(child: Text('No videos here.'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final v = shown[i];
                      final current = vm.playback?.videoId == v.id;
                      return ListTile(
                        leading: SizedBox(
                          width: 96,
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: v.isYouTube
                                  ? VideoThumbnail(youtubeId: v.youtubeId)
                                  : ColoredBox(
                                      color:
                                          theme.colorScheme.secondaryContainer,
                                      child: const Icon(Icons.movie_outlined),
                                    ),
                            ),
                          ),
                        ),
                        title: Text(
                          v.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          v.isYouTube
                              ? 'YouTube'
                              : '${v.file!.format} · '
                                    '${TeamVideo.formatBytes(v.file!.size)}',
                        ),
                        trailing: current
                            ? const Icon(Icons.play_circle_outline)
                            : null,
                        onTap: () => Navigator.pop(context, v.id),
                      );
                    },
                  ),
          ),
        ],
      );
    },
  );
}
