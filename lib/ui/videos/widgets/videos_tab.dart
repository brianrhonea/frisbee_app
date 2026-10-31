import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/team_video.dart';
import '../../../routing/routes.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/team_videos_viewmodel.dart';
import 'youtube_player_view.dart';

/// A team's Videos section: YouTube videos shared with the team, newest
/// first, as thumbnails. Tapping one opens its page with the player.
class VideosTab extends StatefulWidget {
  const VideosTab({super.key, required this.viewModel});

  final TeamVideosViewModel viewModel;

  @override
  State<VideosTab> createState() => _VideosTabState();
}

class _VideosTabState extends State<VideosTab> {
  TeamVideosViewModel get vm => widget.viewModel;

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
    if (cmd.error) {
      showErrorSnackBar(context, cmd.result);
      cmd.clearResult();
    }
  }

  Future<void> _delete(TeamVideo v) async {
    if (await confirmDialog(
      context,
      title: 'Remove "${v.title}"?',
      message:
          'It will no longer be listed for the team. The video stays on '
          'YouTube.',
      confirmLabel: 'Remove',
      destructive: true,
    )) {
      vm.deleteVideo.execute(v.id);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) {
      final videos = vm.videos;
      return Scaffold(
        floatingActionButton: vm.canEdit
            ? FloatingActionButton.extended(
                heroTag: 'new-video',
                onPressed: () => context.push(Routes.newVideo(vm.teamId)),
                icon: const Icon(Icons.add_link),
                label: const Text('Add video'),
              )
            : null,
        body: !vm.loaded
            ? const LoadingView()
            : vm.error != null && videos.isEmpty
            ? ErrorView(error: vm.error)
            : videos.isEmpty
            ? EmptyView(
                icon: Icons.video_library_outlined,
                title: 'No videos yet',
                message: vm.canEdit
                    ? 'Upload a video to YouTube (unlisted works), then add '
                          'its link here.'
                    : 'Meeting recordings and film your coaches share will '
                          'show up here.',
              )
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 420,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  mainAxisExtent: 300,
                ),
                itemCount: videos.length,
                itemBuilder: (context, i) => VideoCard(
                  video: videos[i],
                  onOpen: () =>
                      context.push(Routes.video(vm.teamId, videos[i].id)),
                  onEdit: vm.canEdit
                      ? () => context.push(
                          Routes.editVideo(vm.teamId, videos[i].id),
                        )
                      : null,
                  onDelete: vm.canEdit ? () => _delete(videos[i]) : null,
                ),
              ),
      );
    },
  );
}

enum _VideoAction { edit, delete }

/// A video's thumbnail, title, description and who shared it.
class VideoCard extends StatelessWidget {
  const VideoCard({
    super.key,
    required this.video,
    required this.onOpen,
    this.onEdit,
    this.onDelete,
  });

  final TeamVideo video;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final when = video.createdAt;
    final byline = [
      if (video.authorName.isNotEmpty) video.authorName,
      if (when != null) DateFormat.yMMMd().format(when),
    ].join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoThumbnail(youtubeId: video.youtubeId),
                  const Center(child: _PlayBadge()),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          if (video.description.isNotEmpty)
                            Text(
                              video.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          const Spacer(),
                          Text(
                            byline,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onEdit != null || onDelete != null)
                      PopupMenuButton<_VideoAction>(
                        tooltip: 'Video options',
                        onSelected: (a) => switch (a) {
                          _VideoAction.edit => onEdit?.call(),
                          _VideoAction.delete => onDelete?.call(),
                        },
                        itemBuilder: (_) => [
                          if (onEdit != null)
                            const PopupMenuItem(
                              value: _VideoAction.edit,
                              child: Text('Edit'),
                            ),
                          if (onDelete != null)
                            const PopupMenuItem(
                              value: _VideoAction.delete,
                              child: Text('Remove'),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
    child: Padding(
      padding: EdgeInsets.all(8),
      child: Icon(Icons.play_arrow, color: Colors.white, size: 36),
    ),
  );
}
