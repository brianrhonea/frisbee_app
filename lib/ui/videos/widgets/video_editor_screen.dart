import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/team_video.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/video_editor_viewmodel.dart';
import 'youtube_player_view.dart';

/// Adds a YouTube video to the team, or edits one: paste the link, and the
/// title fills in from YouTube.
class VideoEditorScreen extends StatefulWidget {
  const VideoEditorScreen({super.key, required this.viewModel});

  final VideoEditorViewModel viewModel;

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  VideoEditorViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.save.addListener(_onSave);
  }

  @override
  void dispose() {
    vm.save.removeListener(_onSave);
    super.dispose();
  }

  void _onSave() {
    final cmd = vm.save;
    switch (cmd.result) {
      case Ok<String>(:final value):
        cmd.clearResult();
        showSnackBar(context, vm.isNew ? 'Video added' : 'Video saved');
        final page = Routes.video(vm.teamId, value);
        if (!context.canPop()) {
          context.go(page);
        } else if (vm.isNew) {
          context.pushReplacement(page);
        } else {
          context.pop();
        }
      case Error<String>():
        showErrorSnackBar(context, cmd.result);
        cmd.clearResult();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([vm.load, vm.save]),
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        leading: backOr(context, Routes.teamVideos(vm.teamId)),
        title: Text(vm.isNew ? 'Add video' : 'Edit video'),
      ),
      body: vm.load.running
          ? const LoadingView()
          : vm.load.error
          ? ErrorView(error: vm.load.result, onRetry: vm.load.execute)
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: _VideoForm(viewModel: vm),
              ),
            ),
    ),
  );
}

class _VideoForm extends StatefulWidget {
  const _VideoForm({required this.viewModel});

  final VideoEditorViewModel viewModel;

  @override
  State<_VideoForm> createState() => _VideoFormState();
}

class _VideoFormState extends State<_VideoForm> {
  VideoEditorViewModel get vm => widget.viewModel;

  late final _link = TextEditingController(
    text: vm.initial.youtubeId.isEmpty ? '' : vm.initial.watchUrl,
  );
  late final _title = TextEditingController(text: vm.initial.title);
  late final _description = TextEditingController(text: vm.initial.description);

  /// Empty for no folder; a folder that no longer exists counts as none.
  late String _folderId = vm.folders.any((f) => f.id == vm.initial.folderId)
      ? vm.initial.folderId
      : '';

  /// The title YouTube gave, while the field still shows it unchanged.
  String? _autoTitle;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    vm.addListener(_onCheck);
  }

  @override
  void dispose() {
    vm.removeListener(_onCheck);
    _debounce?.cancel();
    _link.dispose();
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Fills the title from YouTube unless the user has typed their own.
  void _onCheck() {
    final title = vm.youTubeTitle;
    if (title == null || title.isEmpty) return;
    final current = _title.text.trim();
    if (current.isEmpty || current == _autoTitle) {
      final fill = title.length > TeamVideo.maxTitle
          ? title.substring(0, TeamVideo.maxTitle)
          : title;
      _title.text = fill;
      _autoTitle = fill;
    }
  }

  void _onLinkChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => vm.checkLink(text),
    );
  }

  void _submit() {
    final upload = vm.source == VideoSource.upload;
    final id = upload ? '' : TeamVideo.youtubeIdFrom(_link.text);
    if (id == null) {
      showErrorSnackBar(
        context,
        Result<void>.error(Exception('Paste a YouTube link.')),
      );
      return;
    }
    vm.save.execute(
      vm.initial.copyWith(
        youtubeId: id,
        folderId: _folderId,
        title: _title.text,
        description: _description.text,
      ),
    );
  }

  /// Picks a video file, and names the video after it if no title is typed.
  Future<void> _pickFile() async {
    await vm.pickFile();
    final name = vm.pickedFile?.name;
    if (name == null || _title.text.trim().isNotEmpty) return;
    final base = VideoFile.baseName(name);
    _title.text = base.length > TeamVideo.maxTitle
        ? base.substring(0, TeamVideo.maxTitle)
        : base;
  }

  bool get _canSubmit {
    if (vm.save.running) return false;
    if (!vm.isNew && !vm.initial.isYouTube) return true;
    return switch (vm.source) {
      VideoSource.youTube => vm.youtubeId != null,
      VideoSource.upload => vm.pickedFile != null && vm.fileProblem == null,
    };
  }

  List<Widget> _youTubeFields() {
    final id = vm.youtubeId;
    return [
      TextField(
        controller: _link,
        autofocus: vm.isNew,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          labelText: 'YouTube link',
          hintText: 'https://youtu.be/…',
          prefixIcon: Icon(Icons.link),
        ),
        onChanged: _onLinkChanged,
        onSubmitted: vm.checkLink,
      ),
      const SizedBox(height: 8),
      _LinkStatus(check: vm.linkCheck, channel: vm.channel),
      if (id != null) ...[
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: VideoThumbnail(youtubeId: id),
          ),
        ),
      ],
    ];
  }

  List<Widget> _uploadFields(BuildContext context) {
    final theme = Theme.of(context);
    final file = vm.pickedFile;
    final problem = vm.fileProblem;
    final progress = vm.uploadProgress;
    return [
      Text(
        'MP4, MOV, MKV and other video files, up to ${TeamVideo.formatBytes(TeamVideo.maxFileBytes)}. The '
        'team has ${TeamVideo.formatBytes(vm.usedBytes)} of '
        '${TeamVideo.formatBytes(TeamVideo.teamQuotaBytes)} used.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: progress != null ? null : _pickFile,
        icon: const Icon(Icons.video_file_outlined),
        label: Text(file == null ? 'Choose video file' : 'Choose another'),
      ),
      if (file != null) ...[
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.movie_outlined),
          title: Text(file.name, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            file.size == null ? '' : TeamVideo.formatBytes(file.size!),
          ),
        ),
      ],
      if (problem != null)
        Text(
          problem,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      if (progress != null) ...[
        const SizedBox(height: 8),
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 4),
        Text(
          'Uploading ${(progress * 100).floor()}%… keep this page open.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([vm, vm.save]),
    builder: (context, _) {
      final editingFile = !vm.isNew && !vm.initial.isYouTube;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (vm.isNew) ...[
            SegmentedButton<VideoSource>(
              segments: const [
                ButtonSegment(
                  value: VideoSource.youTube,
                  icon: Icon(Icons.smart_display_outlined),
                  label: Text('YouTube link'),
                ),
                ButtonSegment(
                  value: VideoSource.upload,
                  icon: Icon(Icons.upload_file_outlined),
                  label: Text('Upload file'),
                ),
              ],
              selected: {vm.source},
              onSelectionChanged: vm.uploadProgress != null
                  ? null
                  : (s) => vm.source = s.single,
            ),
            const SizedBox(height: 16),
          ],
          if (editingFile)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.movie_outlined),
              title: Text(vm.initial.file!.name),
              subtitle: Text(TeamVideo.formatBytes(vm.initial.file!.size)),
            )
          else if (vm.source == VideoSource.upload)
            ..._uploadFields(context)
          else
            ..._youTubeFields(),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            maxLength: TeamVideo.maxTitle,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Title',
              helperText: vm.source == VideoSource.youTube && !editingFile
                  ? 'Filled in from YouTube; change it if you like.'
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _description,
            maxLength: TeamVideo.maxDescription,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              hintText: 'What it covers, timestamps, who should watch…',
              alignLabelWithHint: true,
            ),
          ),
          if (vm.folders.isNotEmpty) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _folderId,
              decoration: const InputDecoration(
                labelText: 'Folder',
                prefixIcon: Icon(Icons.folder_outlined),
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('No folder')),
                for (final f in vm.folders)
                  DropdownMenuItem(value: f.id, child: Text(f.name)),
              ],
              onChanged: vm.uploadProgress != null
                  ? null
                  : (v) => setState(() => _folderId = v ?? ''),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: Text(
              !vm.isNew
                  ? 'Save'
                  : vm.source == VideoSource.upload
                  ? 'Upload video'
                  : 'Add video',
            ),
          ),
        ],
      );
    },
  );
}

class _LinkStatus extends StatelessWidget {
  const _LinkStatus({required this.check, required this.channel});

  final LinkCheck check;
  final String? channel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData? icon, Color color, String text) = switch (check) {
      LinkCheck.empty => (
        null,
        scheme.onSurfaceVariant,
        'Upload to YouTube as Unlisted (or Public), then paste the link.',
      ),
      LinkCheck.invalid => (
        Icons.error_outline,
        scheme.error,
        "That isn't a YouTube video link.",
      ),
      LinkCheck.checking => (
        Icons.hourglass_empty,
        scheme.onSurfaceVariant,
        'Checking with YouTube…',
      ),
      LinkCheck.embeddable => (
        Icons.check_circle_outline,
        Colors.green.shade700,
        channel == null || channel!.isEmpty
            ? 'Ready to play in the app.'
            : 'Ready to play in the app · $channel',
      ),
      LinkCheck.notEmbeddable => (
        Icons.warning_amber_outlined,
        scheme.error,
        "YouTube won't play this one here. Make sure it's Unlisted or "
            'Public (not Private) and that "Allow embedding" is on.',
      ),
      LinkCheck.unknown => (
        Icons.cloud_off_outlined,
        scheme.onSurfaceVariant,
        "Couldn't reach YouTube to check this link. You can still add it.",
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
