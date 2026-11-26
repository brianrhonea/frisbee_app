import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/team_video.dart';
import '../../../domain/models/video_folder.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/team_videos_viewmodel.dart';
import 'youtube_player_view.dart';

/// A team's Videos section: YouTube videos and uploads shared with the
/// team, newest first, as thumbnails, filed in folders. Tapping one opens
/// its page with the player.
class VideosTab extends StatefulWidget {
  const VideosTab({super.key, required this.viewModel});

  final TeamVideosViewModel viewModel;

  @override
  State<VideosTab> createState() => _VideosTabState();
}

class _VideosTabState extends State<VideosTab> {
  TeamVideosViewModel get vm => widget.viewModel;

  late final _commands = [
    vm.deleteVideo,
    vm.moveVideo,
    vm.saveFolder,
    vm.deleteFolder,
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
    for (final cmd in _commands) {
      if (cmd.error) {
        showErrorSnackBar(context, cmd.result);
        cmd.clearResult();
      }
    }
  }

  Future<void> _delete(TeamVideo v) async {
    if (await confirmDialog(
      context,
      title: 'Remove "${v.title}"?',
      message: v.isYouTube
          ? 'It will no longer be listed for the team. The video stays on '
                'YouTube.'
          : 'The uploaded file will be deleted and its space freed.',
      confirmLabel: 'Remove',
      destructive: true,
    )) {
      vm.deleteVideo.execute(v.id);
    }
  }

  Future<void> _move(TeamVideo v) async {
    final folderId = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Move "${v.title}" to'),
        children: [
          for (final (id, name) in [
            ('', 'No folder'),
            for (final f in vm.folders) (f.id, f.name),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, id),
              child: Row(
                children: [
                  Icon(
                    id.isEmpty ? Icons.inbox_outlined : Icons.folder_outlined,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(name)),
                  if ((vm.folderOf(v)?.id ?? '') == id) const Icon(Icons.check),
                ],
              ),
            ),
        ],
      ),
    );
    if (folderId == null || folderId == (vm.folderOf(v)?.id ?? '')) return;
    vm.moveVideo.execute((videoId: v.id, folderId: folderId));
  }

  Future<void> _newFolder() async {
    final name = await _folderName(context, title: 'New folder');
    if (name == null) return;
    await vm.saveFolder.execute(VideoFolder(id: '', name: name));
    if (vm.saveFolder.result case Ok<String>(:final value)) {
      vm.saveFolder.clearResult();
      vm.filter = InFolder(value);
    }
  }

  Future<void> _renameFolder(VideoFolder f) async {
    final name = await _folderName(
      context,
      title: 'Rename folder',
      initial: f.name,
      confirmLabel: 'Rename',
    );
    if (name == null || name == f.name) return;
    vm.saveFolder.execute(VideoFolder(id: f.id, name: name));
  }

  Future<void> _deleteFolder(VideoFolder f) async {
    final n = vm.countIn(InFolder(f.id));
    if (await confirmDialog(
      context,
      title: 'Delete the "${f.name}" folder?',
      message: n == 0
          ? 'It has no videos.'
          : 'Its ${n == 1 ? 'video moves' : '$n videos move'} to Unsorted; '
                'no videos are deleted.',
      confirmLabel: 'Delete folder',
      destructive: true,
    )) {
      vm.deleteFolder.execute(f.id);
    }
  }

  Widget _list(BuildContext context, List<TeamVideo> videos) {
    final c = AppColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Material(
              color: c.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(cardRadius),
                side: BorderSide(color: c.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (i, v) in videos.indexed) ...[
                    if (i > 0) Divider(height: 1, color: c.border),
                    VideoCard(
                      video: v,
                      // Inside a folder, every row would say the same thing.
                      folderName: vm.filter is AllVideos
                          ? vm.folderOf(v)?.name
                          : null,
                      onOpen: () => context.push(Routes.video(vm.teamId, v.id)),
                      onEdit: vm.canEdit
                          ? () =>
                                context.push(Routes.editVideo(vm.teamId, v.id))
                          : null,
                      onMove: vm.canEdit && vm.folders.isNotEmpty
                          ? () => _move(v)
                          : null,
                      onDelete: vm.canEdit ? () => _delete(v) : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _videos(BuildContext context) {
    final videos = vm.visibleVideos;
    if (videos.isNotEmpty) return _list(context, videos);
    if (vm.videos.isEmpty) {
      return EmptyView(
        icon: Icons.video_library_outlined,
        title: 'No videos yet',
        message: vm.canEdit
            ? 'Add a YouTube link (unlisted works) or upload a video file.'
            : 'Meeting recordings and film your coaches share will show up '
                  'here.',
      );
    }
    return EmptyView(
      icon: Icons.folder_open_outlined,
      title: switch (vm.filter) {
        UnsortedVideos() => 'Every video is in a folder',
        _ => 'Nothing in ${vm.currentFolder?.name ?? 'this folder'} yet',
      },
      message: vm.canEdit
          ? 'Add a video here, or use ⋮ → Move to folder on any video.'
          : 'Videos your coaches file here will show up.',
    );
  }

  Widget _body(BuildContext context) {
    if (!vm.loaded) return const LoadingView();
    if (vm.error != null && vm.videos.isEmpty) {
      return ErrorView(error: vm.error);
    }
    final current = vm.currentFolder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (vm.canEdit && vm.videos.isNotEmpty)
          _StorageUsed(bytes: vm.usedBytes),
        if (vm.canEdit || vm.folders.isNotEmpty)
          _FolderBar(viewModel: vm, onNew: vm.canEdit ? _newFolder : null),
        if (vm.videos.isNotEmpty || current != null)
          _ListHeader(
            title: switch (vm.filter) {
              AllVideos() => 'All videos',
              UnsortedVideos() => 'Unsorted',
              InFolder() => current?.name ?? 'Folder',
            },
            count: vm.visibleVideos.length,
            folder: current,
            onRename: vm.canEdit ? _renameFolder : null,
            onDelete: vm.canEdit ? _deleteFolder : null,
          ),
        Expanded(child: _videos(context)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) => Scaffold(
      floatingActionButton: vm.canEdit
          ? FloatingActionButton.extended(
              heroTag: 'new-video',
              onPressed: () => context.push(
                Routes.newVideo(vm.teamId, folderId: vm.currentFolder?.id),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add video'),
            )
          : null,
      body: _body(context),
    ),
  );
}

/// Asks for a folder name; null when cancelled.
Future<String?> _folderName(
  BuildContext context, {
  required String title,
  String initial = '',
  String confirmLabel = 'Create',
}) => showDialog<String>(
  context: context,
  builder: (_) => _FolderNameDialog(
    title: title,
    initial: initial,
    confirmLabel: confirmLabel,
  ),
);

class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog({
    required this.title,
    required this.initial,
    required this.confirmLabel,
  });

  final String title;
  final String initial;
  final String confirmLabel;

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _name,
      autofocus: true,
      maxLength: VideoFolder.maxName,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        labelText: 'Name',
        hintText: 'Film review, Game film, Highlights…',
      ),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _done(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _name.text.trim().isEmpty ? null : _done,
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}

enum _FolderAction { rename, delete }

/// Chips to show all videos, one folder, or unsorted ones; admins also
/// add folders here.
class _FolderBar extends StatelessWidget {
  const _FolderBar({required this.viewModel, this.onNew});

  final TeamVideosViewModel viewModel;
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final c = AppColors.of(context);
    Widget chip(VideoFilter f, String label, {IconData? icon}) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: icon == null
            ? null
            : Icon(
                icon,
                size: 18,
                color: vm.filter == f ? c.onChipOn : c.accent,
              ),
        label: Text('$label (${vm.countIn(f)})'),
        selected: vm.filter == f,
        showCheckmark: false,
        onSelected: (_) => vm.filter = f,
      ),
    );
    final unsorted = vm.countIn(const UnsortedVideos());
    return SizedBox(
      height: 60,
      // Not a ListView: every chip is built, so a team's few folders
      // all stay findable and focusable while scrolled off.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            chip(const AllVideos(), 'All'),
            for (final f in vm.folders)
              chip(InFolder(f.id), f.name, icon: Icons.folder_outlined),
            if (vm.folders.isNotEmpty &&
                (unsorted > 0 || vm.filter is UnsortedVideos))
              chip(const UnsortedVideos(), 'Unsorted'),
            if (onNew != null)
              ActionChip(
                avatar: Icon(
                  Icons.create_new_folder_outlined,
                  size: 18,
                  color: c.accent,
                ),
                label: Text('New folder', style: TextStyle(color: c.accent)),
                side: BorderSide(color: c.border2),
                onPressed: onNew,
              ),
          ],
        ),
      ),
    );
  }
}

/// The heading over the list: "All videos", the folder's name or
/// "Unsorted", its count, and for admins the open folder's options.
class _ListHeader extends StatelessWidget {
  const _ListHeader({
    required this.title,
    required this.count,
    this.folder,
    this.onRename,
    this.onDelete,
  });

  final String title;
  final int count;
  final VideoFolder? folder;
  final void Function(VideoFolder)? onRename;
  final void Function(VideoFolder)? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final current = folder;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, minHeight: 40),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: c.ink,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  count == 1 ? '1 video' : '$count videos',
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ),
              if (current != null && (onRename != null || onDelete != null))
                PopupMenuButton<_FolderAction>(
                  tooltip: 'Folder options',
                  icon: Icon(Icons.more_vert, color: c.ink2),
                  onSelected: (a) => switch (a) {
                    _FolderAction.rename => onRename?.call(current),
                    _FolderAction.delete => onDelete?.call(current),
                  },
                  itemBuilder: (_) => [
                    if (onRename != null)
                      PopupMenuItem(
                        value: _FolderAction.rename,
                        child: Text('Rename "${current.name}"'),
                      ),
                    if (onDelete != null)
                      PopupMenuItem(
                        value: _FolderAction.delete,
                        child: Text('Delete "${current.name}"'),
                      ),
                  ],
                )
              else
                const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Admins' view of how much of the team's upload space is used.
class _StorageUsed extends StatelessWidget {
  const _StorageUsed({required this.bytes});

  final int bytes;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final fraction = (bytes / TeamVideo.teamQuotaBytes).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Uploads: ${TeamVideo.formatBytes(bytes)} of '
            '${TeamVideo.formatBytes(TeamVideo.teamQuotaBytes)} used',
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: c.field,
              // Nearly full is the admin's to deal with: amber.
              color: fraction > 0.9 ? c.highlight : c.accent,
            ),
          ),
        ],
      ),
    );
  }
}

enum _VideoAction { edit, move, delete }

/// A video's row: its thumbnail, title, description and who shared it.
class VideoCard extends StatelessWidget {
  const VideoCard({
    super.key,
    required this.video,
    required this.onOpen,
    this.folderName,
    this.onEdit,
    this.onMove,
    this.onDelete,
  });

  final TeamVideo video;

  /// Shown in the byline, e.g. when listing every folder.
  final String? folderName;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final when = video.createdAt;
    final byline = [
      ?folderName,
      if (video.authorName.isNotEmpty) video.authorName,
      if (when != null) DateFormat.yMMMd().format(when),
    ].join(' · ');
    final hasMenu = onEdit != null || onMove != null || onDelete != null;
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 12, hasMenu ? 0 : 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 128,
                height: 72,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (video.file case final f?)
                      _FileThumbnail(file: f)
                    else ...[
                      VideoThumbnail(youtubeId: video.youtubeId),
                      const Center(child: _PlayBadge()),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  if (video.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      video.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.ink2),
                    ),
                  ],
                  if (byline.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      byline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ],
              ),
            ),
            if (hasMenu)
              PopupMenuButton<_VideoAction>(
                tooltip: 'Video options',
                icon: Icon(Icons.more_vert, color: c.muted),
                onSelected: (a) => switch (a) {
                  _VideoAction.edit => onEdit?.call(),
                  _VideoAction.move => onMove?.call(),
                  _VideoAction.delete => onDelete?.call(),
                },
                itemBuilder: (_) => [
                  if (onEdit != null)
                    const PopupMenuItem(
                      value: _VideoAction.edit,
                      child: Text('Edit'),
                    ),
                  if (onMove != null)
                    const PopupMenuItem(
                      value: _VideoAction.move,
                      child: Text('Move to folder'),
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
    );
  }
}

/// A small play button over a thumbnail photo (white on a dark scrim,
/// like the video it covers).
class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
    child: Padding(
      padding: EdgeInsets.all(AppSpace.xs),
      child: Icon(Icons.play_arrow, color: Colors.white, size: 24),
    ),
  );
}

/// Uploads have no thumbnail; this shows what kind of video it is instead.
class _FileThumbnail extends StatelessWidget {
  const _FileThumbnail({required this.file});

  final VideoFile file;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.field,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          Center(child: Icon(Icons.movie_outlined, color: c.muted, size: 26)),
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: c.feature,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${file.format} · ${TeamVideo.formatBytes(file.size)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: c.onFeature,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
