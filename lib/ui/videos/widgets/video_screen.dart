import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/models/team_video.dart';
import '../../../routing/routes.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/video_viewmodel.dart';
import 'file_video_player.dart';
import 'youtube_player_view.dart';

/// A team video: the player (YouTube's, or media_kit for uploads), its
/// title and description.
class VideoScreen extends StatefulWidget {
  const VideoScreen({
    super.key,
    required this.viewModel,
    this.player = youTubePlayer,
    this.filePlayer = fileVideoPlayer,
  });

  final VideoViewModel viewModel;
  final YouTubePlayerBuilder player;
  final FileVideoPlayerBuilder filePlayer;

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  VideoViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.deleteVideo.addListener(_onDelete);
  }

  @override
  void dispose() {
    vm.deleteVideo.removeListener(_onDelete);
    super.dispose();
  }

  void _onDelete() {
    final cmd = vm.deleteVideo;
    if (cmd.completed) {
      cmd.clearResult();
      showSnackBar(context, 'Video removed');
      _exit();
    } else if (cmd.error) {
      showErrorSnackBar(context, cmd.result);
      cmd.clearResult();
    }
  }

  void _exit() => context.canPop()
      ? context.pop()
      : context.go(Routes.teamVideos(vm.teamId));

  Future<void> _delete() async {
    if (await confirmDialog(
      context,
      title: 'Remove this video?',
      message: vm.video?.isYouTube ?? true
          ? 'It will no longer be listed for the team. The video stays on '
                'YouTube.'
          : 'The uploaded file will be deleted and its space freed.',
      confirmLabel: 'Remove',
      destructive: true,
    )) {
      vm.deleteVideo.execute();
    }
  }

  Widget _player(TeamVideo video) {
    if (video.isYouTube) return widget.player(video.youtubeId);
    if (vm.fileUrl case final url?) return widget.filePlayer(url);
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: vm.fileError != null
              ? const Text(
                  "Couldn't load this video.",
                  style: TextStyle(color: Colors.white),
                )
              : const CircularProgressIndicator(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) {
      final video = vm.video;
      final leading = backOr(context, Routes.teamVideos(vm.teamId));
      if (!vm.loaded) {
        return Scaffold(
          appBar: AppBar(leading: leading),
          body: const LoadingView(),
        );
      }
      if (video == null) {
        return Scaffold(
          appBar: AppBar(leading: leading),
          body: vm.error != null
              ? ErrorView(error: vm.error)
              : const EmptyView(
                  icon: Icons.videocam_off_outlined,
                  title: 'Video not available',
                  message: 'It may have been removed.',
                ),
        );
      }
      final theme = Theme.of(context);
      final when = video.createdAt;
      final byline = [
        if (video.authorName.isNotEmpty) 'Shared by ${video.authorName}',
        if (when != null) DateFormat.yMMMd().format(when),
        if (video.file case final f?) TeamVideo.formatBytes(f.size),
      ].join(' · ');
      return Scaffold(
        appBar: AppBar(
          leading: leading,
          title: const Text('Video'),
          actions: [
            if (vm.canEdit) ...[
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () =>
                    context.push(Routes.editVideo(vm.teamId, video.id)),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: vm.deleteVideo.running ? null : _delete,
              ),
            ],
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                // Keyed by video, so editing the link swaps players.
                KeyedSubtree(
                  key: ValueKey(video.file?.path ?? video.youtubeId),
                  child: _player(video),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(video.title, style: theme.textTheme.titleLarge),
                      if (byline.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            byline,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (video.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: SelectableText(video.description),
                        ),
                      const SizedBox(height: 12),
                      if (video.isYouTube)
                        TextButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(video.watchUrl),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open on YouTube'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
