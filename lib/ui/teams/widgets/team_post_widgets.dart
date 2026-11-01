import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/models/chat.dart';
import '../../../domain/models/team_post.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart';

enum _PostAction { edit, delete }

/// Loads a post photo's bytes.
typedef ImageLoader = Future<Result<Uint8List>> Function(ChatAttachment image);

/// A post: author and team, title, text, photos, place and links.
/// [teamName] names the team it's from (on the community feed); [onEdit]
/// and [onDelete] are for team admins; [showVisibility] marks each post
/// public or members-only.
class TeamPostCard extends StatelessWidget {
  const TeamPostCard({
    super.key,
    required this.post,
    required this.loadImage,
    this.teamName,
    this.onOpenTeam,
    this.showVisibility = false,
    this.onEdit,
    this.onDelete,
    this.now,
  });

  final TeamPost post;
  final ImageLoader loadImage;
  final String? teamName;

  /// Opens the team's page from its name.
  final VoidCallback? onOpenTeam;
  final bool showVisibility;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// For "2 hours ago"; defaults to the current time.
  final DateTime? now;

  Future<void> _open(BuildContext context, Uri uri) =>
      openPostLink(context, uri);

  Uri _mapFor(String place) => Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': place,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final when = post.createdAt;
    final author = post.authorName.isEmpty ? 'Team admin' : post.authorName;
    final byline = [
      ?teamName,
      if (when != null) timeAgo(when, now ?? DateTime.now()),
      if (post.edited) 'edited',
    ].join(' · ');
    final images = post.images;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                PersonAvatar(name: author, radius: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        author,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: c.ink,
                        ),
                      ),
                      if (byline.isNotEmpty)
                        InkWell(
                          onTap: onOpenTeam,
                          child: Text(
                            byline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: c.muted),
                          ),
                        ),
                    ],
                  ),
                ),
                if (showVisibility)
                  Tooltip(
                    message: post.isPublic
                        ? 'Anyone who finds the team can see this'
                        : 'Only team members can see this',
                    child: Icon(
                      post.isPublic ? Icons.public : Icons.lock_outline,
                      size: 15,
                      color: c.muted,
                    ),
                  ),
                if (onEdit != null || onDelete != null)
                  PopupMenuButton<_PostAction>(
                    tooltip: 'Post options',
                    icon: Icon(Icons.more_horiz, color: c.muted),
                    onSelected: (a) => switch (a) {
                      _PostAction.edit => onEdit?.call(),
                      _PostAction.delete => onDelete?.call(),
                    },
                    itemBuilder: (_) => [
                      if (onEdit != null)
                        const PopupMenuItem(
                          value: _PostAction.edit,
                          child: Text('Edit'),
                        ),
                      if (onDelete != null)
                        const PopupMenuItem(
                          value: _PostAction.delete,
                          child: Text('Delete'),
                        ),
                    ],
                  )
                else
                  const SizedBox(width: 10),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (post.title.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      post.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: -0.3,
                        color: c.ink,
                      ),
                    ),
                  ],
                  if (post.body.isNotEmpty) ...[
                    SizedBox(height: post.title.isEmpty ? 12 : 6),
                    SelectableText(
                      post.body,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: c.ink,
                      ),
                    ),
                  ],
                  if (images.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    if (images.length == 1)
                      PostImage(
                        image: images.single,
                        loadImage: loadImage,
                        aspectRatio: 16 / 10,
                      )
                    else
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        children: [
                          for (final i in images)
                            PostImage(
                              image: i,
                              loadImage: loadImage,
                              aspectRatio: 1,
                            ),
                        ],
                      ),
                  ],
                  if (post.location.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    PostLinkRow(
                      icon: Icons.place_outlined,
                      text: post.location,
                      tooltip: 'Open in Maps',
                      onTap: () => _open(context, _mapFor(post.location)),
                    ),
                  ],
                  for (final l in post.links)
                    PostLinkRow(
                      icon: Icons.link,
                      text: Uri.parse(l).host.isEmpty ? l : _short(l),
                      tooltip: l,
                      onTap: () => _open(context, Uri.parse(l)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _short(String link) => shortLink(link);
}

/// Opens a post link in the browser, or says it couldn't.
Future<void> openPostLink(BuildContext context, Uri uri) async {
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
      context.mounted) {
    showErrorSnackBar(
      context,
      Result<void>.error(Exception("Couldn't open $uri")),
    );
  }
}

/// "example.com/page" without the scheme or a trailing slash.
String shortLink(String link) => link
    .replaceFirst(RegExp(r'^https?://(www\.)?'), '')
    .replaceFirst(RegExp(r'/$'), '');

/// A tappable place or web link under a post.
class PostLinkRow extends StatelessWidget {
  const PostLinkRow({
    super.key,
    required this.icon,
    required this.text,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A post photo thumbnail; tap to see it full size.
class PostImage extends StatefulWidget {
  const PostImage({
    super.key,
    required this.image,
    required this.loadImage,
    this.size = 156,
    this.aspectRatio,
  });

  final ChatAttachment image;
  final ImageLoader loadImage;

  /// Width and height of a square photo, when [aspectRatio] is null.
  final double size;

  /// Fills the available width at this shape instead of [size].
  final double? aspectRatio;

  @override
  State<PostImage> createState() => _PostImageState();
}

class _PostImageState extends State<PostImage> {
  late var _data = widget.loadImage(widget.image);

  @override
  void didUpdateWidget(PostImage old) {
    super.didUpdateWidget(old);
    if (old.image.path != widget.image.path) {
      _data = widget.loadImage(widget.image);
    }
  }

  void _retry() => setState(() => _data = widget.loadImage(widget.image));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = widget.aspectRatio;
    Widget box(Widget child) => ratio == null
        ? SizedBox.square(dimension: widget.size, child: child)
        : AspectRatio(aspectRatio: ratio, child: child);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: FutureBuilder(
          future: _data,
          builder: (context, snap) => switch (snap.data) {
            null => box(const Center(child: CircularProgressIndicator())),
            Error() => box(
              IconButton(
                tooltip: "Couldn't load photo. Retry",
                onPressed: _retry,
                icon: const Icon(Icons.broken_image_outlined),
              ),
            ),
            Ok(:final value) => box(
              InkWell(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => Dialog(
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        InteractiveViewer(child: Image.memory(value)),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: IconButton.filledTonal(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                child: Image.memory(
                  value,
                  fit: BoxFit.cover,
                  semanticLabel: widget.image.name,
                ),
              ),
            ),
          },
        ),
      ),
    );
  }
}

/// Writes or edits a post; pops with the draft or null. [pickImages] opens
/// the photo picker.
class PostEditorDialog extends StatefulWidget {
  const PostEditorDialog({
    super.key,
    required this.pickImages,
    required this.loadImage,
    this.initial,
    this.suggested = false,
    this.allowPublic = true,
  });

  /// Offer the Public switch. A private group's posts are members-only.
  final bool allowPublic;

  /// The post being edited; null for a new one.
  final TeamPost? initial;

  /// [initial] is a suggested new post, not one being edited.
  final bool suggested;
  final Future<Result<List<NewAttachment>>> Function() pickImages;
  final ImageLoader loadImage;

  @override
  State<PostEditorDialog> createState() => _PostEditorDialogState();
}

class _PostEditorDialogState extends State<PostEditorDialog> {
  late final bool _isNew = widget.initial == null || widget.suggested;
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initial?.title);
  late final _body = TextEditingController(text: widget.initial?.body);
  late final _location = TextEditingController(text: widget.initial?.location);
  final _link = TextEditingController();
  late bool _public = widget.initial?.isPublic ?? false;
  late final List<String> _links = [...?widget.initial?.links];
  late final List<ChatAttachment> _kept = [...?widget.initial?.images];
  final List<NewAttachment> _added = [];
  String? _linkError;
  bool _picking = false;

  int get _imageCount => _kept.length + _added.length;

  @override
  void dispose() {
    for (final c in [_title, _body, _location, _link]) {
      c.dispose();
    }
    super.dispose();
  }

  void _addLink() {
    if (_link.text.trim().isEmpty) return;
    final link = TeamPost.normalizeLink(_link.text);
    setState(() {
      if (link == null) {
        _linkError = 'Enter a web address, like example.com/tryouts';
      } else if (_links.length >= TeamPost.maxLinks) {
        _linkError = 'Up to ${TeamPost.maxLinks} links';
      } else {
        _linkError = null;
        if (!_links.contains(link)) _links.add(link);
        _link.clear();
      }
    });
  }

  Future<void> _addPhotos() async {
    setState(() => _picking = true);
    final result = await widget.pickImages();
    if (!mounted) return;
    setState(() => _picking = false);
    switch (result) {
      case Ok(:final value):
        final room = TeamPost.maxImages - _imageCount;
        setState(() => _added.addAll(value.take(room)));
        if (value.length > room) {
          showErrorSnackBar(
            context,
            Result<void>.error(
              Exception('Posts can have up to ${TeamPost.maxImages} photos.'),
            ),
          );
        }
      case Error():
        showErrorSnackBar(context, result);
    }
  }

  void _submit() {
    // A link typed but not added still counts.
    if (_link.text.trim().isNotEmpty) _addLink();
    if (_linkError != null) return;
    if (!_formKey.currentState!.validate()) return;
    final post = (widget.initial ?? const TeamPost(id: '')).copyWith(
      title: _title.text.trim(),
      body: _body.text.trim(),
      location: _location.text.trim(),
      links: List.of(_links),
      images: List.of(_kept),
      isPublic: _public && widget.allowPublic,
    );
    Navigator.pop(context, PostDraft(post: post, newImages: List.of(_added)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_isNew ? 'New post' : 'Edit post'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _title,
                  maxLength: 100,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Title (optional)',
                  ),
                ),
                TextFormField(
                  controller: _body,
                  autofocus: _isNew,
                  minLines: 4,
                  maxLines: 10,
                  maxLength: 5000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Post',
                    hintText: 'Tryouts, fees, field changes, results…',
                    alignLabelWithHint: true,
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) && _imageCount == 0
                      ? 'Write something or add a photo'
                      : null,
                ),
                TextFormField(
                  controller: _location,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Location (optional)',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
                TextField(
                  controller: _link,
                  keyboardType: TextInputType.url,
                  enabled: _links.length < TeamPost.maxLinks,
                  decoration: InputDecoration(
                    labelText: 'Add a link',
                    hintText: 'example.com/tryouts',
                    prefixIcon: const Icon(Icons.link),
                    errorText: _linkError,
                    suffixIcon: IconButton(
                      tooltip: 'Add link',
                      icon: const Icon(Icons.add),
                      onPressed: _addLink,
                    ),
                  ),
                  onChanged: (_) {
                    if (_linkError != null) setState(() => _linkError = null);
                  },
                  onSubmitted: (_) => _addLink(),
                ),
                if (_links.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final l in _links)
                        InputChip(
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: Text(l, overflow: TextOverflow.ellipsis),
                          ),
                          onDeleted: () => setState(() => _links.remove(l)),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('Photos', style: theme.textTheme.titleSmall),
                    const SizedBox(width: 8),
                    // Shrinks on narrow phones instead of overflowing.
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed:
                              _picking || _imageCount >= TeamPost.maxImages
                              ? null
                              : _addPhotos,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: Text(
                            'Add photos ($_imageCount/${TeamPost.maxImages})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_imageCount > 0)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final i in _kept)
                        _RemovablePhoto(
                          onRemove: () => setState(() => _kept.remove(i)),
                          child: PostImage(
                            image: i,
                            loadImage: widget.loadImage,
                            size: 96,
                          ),
                        ),
                      for (final a in _added)
                        _RemovablePhoto(
                          onRemove: () => setState(() => _added.remove(a)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(
                              a.bytes,
                              width: 96,
                              height: 96,
                              fit: BoxFit.cover,
                              semanticLabel: a.name,
                            ),
                          ),
                        ),
                    ],
                  ),
                if (widget.allowPublic)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.public),
                    title: const Text('Public'),
                    subtitle: Text(
                      _public
                          ? 'Anyone who finds the team can see it'
                          : 'Only team members can see it',
                    ),
                    value: _public,
                    onChanged: (v) => setState(() => _public = v),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(_isNew ? 'Post' : 'Save')),
      ],
    );
  }
}

class _RemovablePhoto extends StatelessWidget {
  const _RemovablePhoto({required this.child, required this.onRemove});

  final Widget child;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      child,
      Positioned(
        top: 2,
        right: 2,
        child: IconButton.filledTonal(
          visualDensity: VisualDensity.compact,
          tooltip: 'Remove photo',
          iconSize: 16,
          onPressed: onRemove,
          icon: const Icon(Icons.close),
        ),
      ),
    ],
  );
}
