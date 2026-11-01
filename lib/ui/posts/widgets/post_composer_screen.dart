import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/chat.dart';
import '../../../domain/models/team_post.dart';
import '../../../domain/models/user_post.dart';
import '../../../domain/models/workout.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../teams/widgets/team_post_widgets.dart';
import '../view_models/post_composer_viewmodel.dart';
import 'post_widgets.dart';

/// Writes a post or shares a workout, full screen.
class PostComposerScreen extends StatefulWidget {
  const PostComposerScreen({super.key, required this.viewModel});

  final PostComposerViewModel viewModel;

  @override
  State<PostComposerScreen> createState() => _PostComposerScreenState();
}

/// One editable exercise row.
class _ExerciseRow {
  _ExerciseRow([WorkoutExercise? e])
    : name = TextEditingController(text: e?.name),
      sets = TextEditingController(text: e?.sets?.toString()),
      reps = TextEditingController(text: e?.reps?.toString()),
      weight = TextEditingController(text: e?.weight);

  final TextEditingController name, sets, reps, weight;

  WorkoutExercise get value => WorkoutExercise(
    name: name.text.trim(),
    sets: int.tryParse(sets.text.trim()),
    reps: int.tryParse(reps.text.trim()),
    weight: weight.text.trim(),
  );

  bool get isBlank =>
      name.text.trim().isEmpty &&
      sets.text.trim().isEmpty &&
      reps.text.trim().isEmpty &&
      weight.text.trim().isEmpty;

  void dispose() {
    for (final c in [name, sets, reps, weight]) {
      c.dispose();
    }
  }
}

class _PostComposerScreenState extends State<PostComposerScreen> {
  PostComposerViewModel get vm => widget.viewModel;

  final _formKey = GlobalKey<FormState>();
  final _body = TextEditingController();
  final _link = TextEditingController();
  final _minutes = TextEditingController();
  final _distance = TextEditingController();
  final _exercises = <_ExerciseRow>[];
  final _links = <String>[];
  final _kept = <ChatAttachment>[];
  final _added = <NewAttachment>[];
  late bool _workout = vm.startWithWorkout;
  WorkoutActivity _activity = WorkoutActivity.run;
  int? _effort;
  String? _tagKey;
  String? _tagName;
  String? _linkError;
  bool _picking = false;
  bool _filled = false;

  int get _imageCount => _kept.length + _added.length;

  @override
  void initState() {
    super.initState();
    vm.addListener(_fill);
    vm.save.addListener(_onSave);
    _fill();
  }

  @override
  void dispose() {
    vm.removeListener(_fill);
    vm.save.removeListener(_onSave);
    for (final c in [_body, _link, _minutes, _distance]) {
      c.dispose();
    }
    for (final r in _exercises) {
      r.dispose();
    }
    super.dispose();
  }

  /// Copies the post being edited into the form, once it has loaded.
  void _fill() {
    if (_filled || !vm.loaded) return;
    _filled = true;
    final p = vm.initial;
    if (p == null) return;
    setState(() {
      _body.text = p.body;
      _links.addAll(p.links);
      _kept.addAll(p.images);
      _tagKey = p.tournamentKey;
      _tagName = p.tournamentName;
      final w = p.workout;
      _workout = w != null;
      if (w != null) {
        _activity = w.activity;
        _minutes.text = '${w.durationMinutes}';
        _distance.text = w.distanceKm?.toString() ?? '';
        _effort = w.effort;
        _exercises.addAll(w.exercises.map(_ExerciseRow.new));
      }
    });
  }

  void _onSave() {
    final cmd = vm.save;
    switch (cmd.result) {
      case Ok(:final value):
        cmd.clearResult();
        if (vm.isNew) {
          context.pushReplacement(Routes.post(value));
        } else {
          context.pop();
        }
      case Error():
        showErrorSnackBar(context, cmd.result);
        cmd.clearResult();
      case null:
        break;
    }
  }

  void _addLink() {
    if (_link.text.trim().isEmpty) return;
    final link = TeamPost.normalizeLink(_link.text);
    setState(() {
      if (link == null) {
        _linkError = 'Enter a web address, like example.com/video';
      } else if (_links.length >= UserPost.maxLinks) {
        _linkError = 'Up to ${UserPost.maxLinks} links';
      } else {
        _linkError = null;
        if (!_links.contains(link)) _links.add(link);
        _link.clear();
      }
    });
  }

  Future<void> _addPhotos() async {
    setState(() => _picking = true);
    final result = await vm.pickImages();
    if (!mounted) return;
    setState(() => _picking = false);
    switch (result) {
      case Ok(:final value):
        final room = UserPost.maxImages - _imageCount;
        setState(() => _added.addAll(value.take(room)));
        if (value.length > room) {
          showSnackBar(
            context,
            'Posts can have up to ${UserPost.maxImages} photos.',
          );
        }
      case Error():
        showErrorSnackBar(context, result);
    }
  }

  Workout get _workoutValue => Workout(
    activity: _activity,
    durationMinutes: int.tryParse(_minutes.text.trim()) ?? 0,
    distanceKm: double.tryParse(_distance.text.trim().replaceAll(',', '.')),
    effort: _effort,
    exercises: [
      for (final r in _exercises)
        if (!r.isBlank) r.value,
    ],
  );

  void _submit() {
    if (_link.text.trim().isNotEmpty) _addLink();
    if (_linkError != null) return;
    if (!_formKey.currentState!.validate()) return;
    final post = (vm.initial ?? const UserPost(id: '')).copyWith(
      body: _body.text.trim(),
      links: List.of(_links),
      images: List.of(_kept),
      workout: () => _workout ? _workoutValue : null,
      tournamentKey: () => _tagKey,
      tournamentName: () => _tagKey == null ? null : _tagName,
    );
    vm.save.execute(UserPostDraft(post: post, newImages: List.of(_added)));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([vm, vm.save]),
    builder: (context, _) {
      final title = vm.isNew
          ? (_workout ? 'Share a workout' : 'New post')
          : 'Edit post';
      if (!vm.loaded) {
        return Scaffold(appBar: AppBar(), body: const LoadingView());
      }
      if (vm.loadError != null || !vm.canEdit) {
        return Scaffold(
          appBar: AppBar(),
          body: vm.loadError == null
              ? const EmptyView(
                  icon: Icons.edit_off_outlined,
                  title: "Can't edit this post",
                  message: "It's been deleted, or it isn't yours.",
                )
              : ErrorView(error: vm.loadError),
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: vm.save.running ? null : _submit,
                child: Text(vm.isNew ? 'Post' : 'Save'),
              ),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ConstrainedContent(
            maxWidth: 640,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                if (vm.save.running) const LinearProgressIndicator(),
                if (vm.isNew)
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.edit_note),
                        label: Text('Post'),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.fitness_center),
                        label: Text('Workout'),
                      ),
                    ],
                    selected: {_workout},
                    onSelectionChanged: (s) =>
                        setState(() => _workout = s.first),
                  ),
                const SizedBox(height: 12),
                if (_workout) ..._workoutFields(context),
                TextFormField(
                  controller: _body,
                  minLines: _workout ? 2 : 4,
                  maxLines: 10,
                  maxLength: UserPost.maxBody,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: _workout ? 'Notes (optional)' : 'Post',
                    hintText: _workout
                        ? 'How did it go?'
                        : 'Share a highlight, a question, a result…',
                    alignLabelWithHint: true,
                  ),
                  validator: (v) =>
                      !_workout &&
                          (v == null || v.trim().isEmpty) &&
                          _imageCount == 0
                      ? 'Write something or add a photo'
                      : null,
                ),
                if (vm.tournaments.isNotEmpty || _tagKey != null) _tagField(),
                const SizedBox(height: 8),
                TextField(
                  controller: _link,
                  keyboardType: TextInputType.url,
                  enabled: _links.length < UserPost.maxLinks,
                  decoration: InputDecoration(
                    labelText: 'Add a link',
                    hintText: 'example.com/highlights',
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'Photos',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _picking || _imageCount >= UserPost.maxImages
                          ? null
                          : _addPhotos,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        'Add photos ($_imageCount/${UserPost.maxImages})',
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
                        _Removable(
                          onRemove: () => setState(() => _kept.remove(i)),
                          child: PostImage(
                            image: i,
                            loadImage: vm.imageData,
                            size: 96,
                          ),
                        ),
                      for (final a in _added)
                        _Removable(
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
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _tagField() {
    final options = [
      for (final t in vm.tournaments) (t.key, t.name),
      if (_tagKey != null && !vm.tournaments.any((t) => t.key == _tagKey))
        (_tagKey!, _tagName ?? 'Tournament'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DropdownButtonFormField<String?>(
        initialValue: _tagKey,
        decoration: const InputDecoration(
          labelText: 'At a tournament (optional)',
          helperText: "Its followers see the post too",
          prefixIcon: Icon(Icons.emoji_events_outlined),
        ),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('None')),
          for (final (key, name) in options)
            DropdownMenuItem<String?>(
              value: key,
              child: Text(name, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => setState(() {
          _tagKey = v;
          _tagName = options.where((o) => o.$1 == v).firstOrNull?.$2;
        }),
      ),
    );
  }

  List<Widget> _workoutFields(BuildContext context) {
    final theme = Theme.of(context);
    return [
      Text('Activity', style: theme.textTheme.titleSmall),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final a in WorkoutActivity.values)
            ChoiceChip(
              avatar: Icon(workoutIcon(a), size: 18),
              label: Text(a.label),
              selected: _activity == a,
              onSelected: (_) => setState(() => _activity = a),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Minutes',
                prefixIcon: Icon(Icons.timer_outlined),
              ),
              validator: (v) {
                final n = int.tryParse(v?.trim() ?? '');
                return n == null || n < 1 || n > Workout.maxMinutes
                    ? 'How long, in minutes'
                    : null;
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _distance,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Distance, km (optional)',
                prefixIcon: Icon(Icons.straighten),
              ),
              validator: (v) {
                final t = v?.trim().replaceAll(',', '.') ?? '';
                if (t.isEmpty) return null;
                final d = double.tryParse(t);
                return d == null || d <= 0 || d > Workout.maxDistanceKm
                    ? 'Enter a distance in km'
                    : null;
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Text('Effort', style: theme.textTheme.titleSmall),
          const SizedBox(width: 8),
          Text(
            _effort == null ? 'Not set' : '$_effort/10',
            style: theme.textTheme.bodySmall,
          ),
          const Spacer(),
          if (_effort != null)
            TextButton(
              onPressed: () => setState(() => _effort = null),
              child: const Text('Clear'),
            ),
        ],
      ),
      Slider(
        value: (_effort ?? 5).toDouble(),
        min: 1,
        max: 10,
        divisions: 9,
        label: '${_effort ?? 5}',
        onChanged: (v) => setState(() => _effort = v.round()),
      ),
      Row(
        children: [
          Text('Exercises', style: theme.textTheme.titleSmall),
          const Spacer(),
          TextButton.icon(
            onPressed: _exercises.length >= Workout.maxExercises
                ? null
                : () => setState(() => _exercises.add(_ExerciseRow())),
            icon: const Icon(Icons.add),
            label: const Text('Add exercise'),
          ),
        ],
      ),
      for (final (i, r) in _exercises.indexed)
        Padding(
          key: ObjectKey(r),
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: TextFormField(
                  controller: r.name,
                  maxLength: WorkoutExercise.maxNameLength,
                  decoration: InputDecoration(
                    labelText: 'Exercise ${i + 1}',
                    counterText: '',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) && !r.isBlank
                      ? 'Name it'
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: _NumberField(
                  controller: r.sets,
                  label: 'Sets',
                  max: 100,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: _NumberField(
                  controller: r.reps,
                  label: 'Reps',
                  max: 1000,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: r.weight,
                  maxLength: WorkoutExercise.maxWeightLength,
                  decoration: const InputDecoration(
                    labelText: 'Weight',
                    counterText: '',
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove exercise',
                onPressed: () => setState(() {
                  _exercises.remove(r);
                  r.dispose();
                }),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      const SizedBox(height: 8),
    ];
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.max,
  });

  final TextEditingController controller;
  final String label;
  final int max;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    validator: (v) {
      final t = v?.trim() ?? '';
      if (t.isEmpty) return null;
      final n = int.tryParse(t);
      return n == null || n < 1 || n > max ? '1–$max' : null;
    },
  );
}

class _Removable extends StatelessWidget {
  const _Removable({required this.child, required this.onRemove});

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
