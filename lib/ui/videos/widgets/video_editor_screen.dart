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
    final id = TeamVideo.youtubeIdFrom(_link.text);
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
        title: _title.text,
        description: _description.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([vm, vm.save]),
    builder: (context, _) {
      final id = vm.youtubeId;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            maxLength: TeamVideo.maxTitle,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Title',
              helperText: 'Filled in from YouTube; change it if you like.',
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
          const SizedBox(height: 16),
          FilledButton(
            onPressed: vm.save.running || id == null ? null : _submit,
            child: Text(vm.isNew ? 'Add video' : 'Save'),
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
