import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'add_photos_button.dart';
import '../../../domain/models/post_prompts.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/workout.dart';
import '../../../utils/result.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart';
import '../../workouts/widgets/record_button.dart';
import '../../workouts/widgets/route_widgets.dart';
import '../../workouts/widgets/workout_fields.dart';
import '../view_models/inline_composer_viewmodel.dart';

/// The composer at the top of Home, written in place (as on the website):
/// type and tap Post. The tools under the box add to the same box: Photo
/// shows the picked photos under the text, Workout the workout's fields.
/// There's no link tool: web addresses typed or pasted in the text show as
/// links. The header shows who's posting (the avatar opens their profile)
/// and, with teams to post to, "Posting to" picks
/// Everyone or a team, whose post adds a title, a place and Public. The
/// draft lives in [viewModel], so it outlasts this widget.
class InlineComposer extends StatefulWidget {
  const InlineComposer({
    super.key,
    required this.viewModel,
    required this.name,
    this.photoUrl,
  });

  final InlineComposerViewModel viewModel;

  /// The user's name and photo, for the avatar.
  final String name;
  final String? photoUrl;

  @override
  State<InlineComposer> createState() => _InlineComposerState();
}

/// Which prompt the next composer shows (in memory: it goes round within a
/// session).
int _promptTurn = 0;

class _InlineComposerState extends State<InlineComposer> {
  InlineComposerViewModel get vm => widget.viewModel;

  late final _body = TextEditingController(text: vm.body);
  late final _title = TextEditingController(text: vm.title);
  late final _place = TextEditingController(text: vm.place);
  final _bodyFocus = FocusNode();
  final _workoutKey = GlobalKey();
  final _photosKey = GlobalKey();

  /// The empty body's hint: the next of [postPrompts] each time it opens.
  final _prompt = postPrompt(_promptTurn++);

  @override
  void initState() {
    super.initState();
    _body.addListener(() => vm.setBody(_body.text));
    _title.addListener(() => vm.setTitle(_title.text));
    _place.addListener(() => vm.setPlace(_place.text));
    vm.addListener(_sync);
    vm.post.addListener(_onPost);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    vm.unit = distanceUnitOf(context);
  }

  @override
  void dispose() {
    vm.removeListener(_sync);
    vm.post.removeListener(_onPost);
    for (final c in [_body, _title, _place]) {
      c.dispose();
    }
    _bodyFocus.dispose();
    super.dispose();
  }

  /// Copies changes the view model made (cleared after posting) into the
  /// fields.
  void _sync() {
    for (final (c, v) in [
      (_body, vm.body),
      (_title, vm.title),
      (_place, vm.place),
    ]) {
      if (c.text != v) c.text = v;
    }
  }

  void _onPost() {
    final cmd = vm.post;
    if (cmd.result case Ok(:final value)) {
      cmd.clearResult();
      FocusScope.of(context).unfocus();
      showSnackBar(
        context,
        value.isTeam ? 'Posted to ${value.teamName}' : 'Posted',
      );
    }
  }

  /// Brings a part that just opened into view, above the keyboard.
  void _reveal(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: const Duration(milliseconds: 200),
        );
      }
    });
  }

  // Its tools (photos, workout, To) keep the keyboard open; Post closes it.
  @override
  Widget build(BuildContext context) =>
      TextFieldTapRegion(child: _composer(context));

  Widget _composer(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) {
      final c = AppColors.of(context);
      final team = vm.team;
      final error = vm.post.error ? vm.post.result : vm.notice;
      final field = InputDecoration(
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        hintStyle: TextStyle(color: c.muted, fontSize: 13.5),
      );
      // While posting nothing can change: the draft is cleared once it's
      // saved, so anything added meanwhile would be lost.
      return AbsorbPointer(
        absorbing: vm.post.running,
        child: Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header: who's posting (the avatar opens their profile) and
              // who to.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Semantics(
                      button: true,
                      label: 'Your profile',
                      child: InkWell(
                        key: const Key('composer-avatar'),
                        customBorder: const CircleBorder(),
                        onTap: () => context.go(Routes.profile),
                        child: PersonAvatar(
                          name: widget.name,
                          photoUrl: widget.photoUrl,
                          radius: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                'Posting to ',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: c.muted,
                                ),
                              ),
                              if (vm.audiences.isNotEmpty)
                                Flexible(
                                  child: _AudienceChip(
                                    teams: vm.audiences,
                                    selected: team,
                                    enabled: !vm.post.running,
                                    onPick: vm.pickAudience,
                                  ),
                                )
                              else
                                const Text(
                                  'Everyone',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Body: the post itself.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (team != null)
                      TextField(
                        controller: _title,
                        maxLength: 100,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        decoration: field.copyWith(
                          hintText: 'Title (optional)',
                          counterText: '',
                        ),
                      ),
                    TextField(
                      key: const Key('composer-body'),
                      controller: _body,
                      focusNode: _bodyFocus,
                      minLines: 2,
                      maxLines: 8,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      // Keeps the tools and Send above the keyboard.
                      scrollPadding: const EdgeInsets.only(
                        top: 20,
                        bottom: 140,
                      ),
                      decoration: field.copyWith(
                        hintText: team != null
                            ? "What's the news for ${team.name}?"
                            : vm.workout != null
                            ? 'How did it go? (optional)'
                            : _prompt,
                      ),
                    ),
                    if (team != null)
                      TextField(
                        controller: _place,
                        maxLength: 200,
                        decoration: field.copyWith(
                          hintText: 'Where (optional)',
                          counterText: '',
                          prefixIcon: Icon(
                            Icons.place_outlined,
                            size: 18,
                            color: c.muted,
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 26,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                // Extras get the card's full width (not under the avatar),
                // so the workout's fields have room on phones.
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (vm.workout case final w?)
                      _WorkoutFields(key: _workoutKey, draft: w, viewModel: vm),
                    if (vm.photos.isNotEmpty)
                      Padding(
                        key: _photosKey,
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final a in vm.photos)
                              _RemovablePhoto(
                                onRemove: () => vm.removePhoto(a),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(
                                    a.bytes,
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.cover,
                                    semanticLabel: a.name,
                                    errorBuilder: (_, _, _) => Container(
                                      width: 72,
                                      height: 72,
                                      color: AppColors.of(context).field,
                                      child: const Icon(Icons.image_outlined),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (vm.tournaments.isNotEmpty) _tagField(),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          errorMessage(error),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (vm.post.running) const LinearProgressIndicator(minHeight: 2),
              Divider(height: 1, color: c.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 10, 2),
                child: Row(
                  children: [
                    Expanded(child: _tools(team)),
                    if (vm.charactersLeft < 300)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          '${vm.charactersLeft}',
                          style: TextStyle(
                            fontSize: 12,
                            color: vm.charactersLeft < 0
                                ? Theme.of(context).colorScheme.error
                                : c.muted,
                          ),
                        ),
                      ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      onPressed: vm.canPost
                          ? () {
                              FocusScope.of(context).unfocus();
                              vm.post.execute();
                            }
                          : null,
                      icon: const Icon(Icons.send, size: 16),
                      label: const Text('Send'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _tools(Team? team) {
    final compact = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      visualDensity: VisualDensity.compact,
      textStyle: const TextStyle(
        fontFamily: appFont,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
    final on = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      visualDensity: VisualDensity.compact,
      backgroundColor: AppColors.of(context).accentSoft,
      textStyle: const TextStyle(
        fontFamily: appFont,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AddPhotosButton(
          style: compact,
          enabled: vm.canAddPhotos,
          canUseCamera: vm.canUseCamera,
          onUpload: () async {
            await vm.addPhotos();
            _reveal(_photosKey);
          },
          onTakePhoto: () async {
            await vm.addPhotos(camera: true);
            _reveal(_photosKey);
          },
        ),
        if (vm.offersWorkout) ...[
          Semantics(
            toggled: vm.workout != null,
            child: TextButton.icon(
              style: vm.workout != null ? on : compact,
              onPressed: () {
                vm.toggleWorkout();
                if (vm.workout != null) _reveal(_workoutKey);
              },
              icon: const Icon(Icons.directions_run, size: 18),
              label: const Text('Workout'),
            ),
          ),
          RecordWorkoutButton(style: compact),
        ],
        if (vm.offersPublic)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilterChip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.public, size: 16),
              label: const Text('Public'),
              tooltip: vm.isPublic
                  ? 'Anyone who finds the team can see it'
                  : 'Only team members can see it',
              selected: vm.isPublic,
              showCheckmark: false,
              onSelected: vm.setPublic,
            ),
          ),
      ],
    );
  }

  Widget _tagField() {
    final options = [for (final t in vm.tournaments) (t.key, t.name)];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DropdownButtonFormField<String?>(
        initialValue: options.any((o) => o.$1 == vm.tagKey) ? vm.tagKey : null,
        isDense: true,
        isExpanded: true,
        decoration: const InputDecoration(
          isDense: true,
          labelText: 'At a tournament (optional)',
          prefixIcon: Icon(Icons.emoji_events_outlined, size: 18),
        ),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('None')),
          for (final (key, name) in options)
            DropdownMenuItem<String?>(
              value: key,
              child: Text(name, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: vm.setTag,
      ),
    );
  }
}

/// "Everyone ▾", after "Posting to": who the post goes to, from a menu.
class _AudienceChip extends StatelessWidget {
  const _AudienceChip({
    required this.teams,
    required this.selected,
    required this.enabled,
    required this.onPick,
  });

  final List<Team> teams;
  final Team? selected;
  final bool enabled;
  final ValueChanged<Team?> onPick;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Who sees this post',
      enabled: enabled,
      initialValue: selected?.id ?? '',
      onSelected: (id) {
        if (id.isEmpty) return onPick(null);
        // A team that left the list while the menu was open: keep the pick.
        final to = teams.where((t) => t.id == id).firstOrNull;
        if (to != null) onPick(to);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: '',
          child: Row(
            children: [
              Icon(Icons.public, size: 20),
              SizedBox(width: 12),
              Text('Everyone'),
            ],
          ),
        ),
        for (final t in teams)
          PopupMenuItem(
            value: t.id,
            child: Row(
              children: [
                TeamBadge(size: 24, community: t.isCommunity),
                const SizedBox(width: 12),
                Flexible(child: Text(t.name, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
      ],
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
        decoration: BoxDecoration(
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                selected?.name ?? 'Everyone',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: c.muted),
          ],
        ),
      ),
    );
  }
}

/// A workout's fields inside the composer: activity, minutes, distance,
/// effort and exercises.
class _WorkoutFields extends StatefulWidget {
  const _WorkoutFields({
    super.key,
    required this.draft,
    required this.viewModel,
  });

  final WorkoutDraft draft;
  final InlineComposerViewModel viewModel;

  @override
  State<_WorkoutFields> createState() => _WorkoutFieldsState();
}

class _WorkoutFieldsState extends State<_WorkoutFields> {
  InlineComposerViewModel get vm => widget.viewModel;
  late final _minutes = TextEditingController(text: widget.draft.minutes);
  late final _distance = TextEditingController(text: widget.draft.distance);

  @override
  void initState() {
    super.initState();
    _minutes.addListener(() => vm.setMinutes(_minutes.text));
    _distance.addListener(() => vm.setDistance(_distance.text));
  }

  @override
  void didUpdateWidget(_WorkoutFields old) {
    super.didUpdateWidget(old);
    // A new workout (removed and added again) starts blank.
    if (!identical(old.draft, widget.draft)) {
      _minutes.text = widget.draft.minutes;
      _distance.text = widget.draft.distance;
    }
  }

  @override
  void dispose() {
    _minutes.dispose();
    _distance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    final w = widget.draft;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
      // A thin outline, not a filled panel: the fields inside are filled.
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(controlRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.directions_run, size: 16, color: c.muted),
              const SizedBox(width: 6),
              Text('Workout', style: theme.textTheme.labelLarge),
              const Spacer(),
              IconButton(
                tooltip: 'Remove workout',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: vm.toggleWorkout,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActivityPicker(
              selected: w.activity,
              onSelected: vm.setActivity,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: WorkoutField(
                    label: 'Minutes',
                    child: TextField(
                      controller: _minutes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'e.g. 45',
                        suffixText: 'min',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: WorkoutField(
                    label: 'Distance (optional)',
                    child: TextField(
                      controller: _distance,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'e.g. 3.1',
                        suffixText: vm.unit.label,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: EffortRow(effort: w.effort, onChanged: vm.setEffort),
          ),
          for (final (i, e) in w.exercises.indexed)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _ExerciseFields(
                key: ObjectKey(e),
                index: i,
                draft: e,
                viewModel: vm,
              ),
            ),
          if (vm.canAddExercise)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                onPressed: vm.addExercise,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add exercise'),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExerciseFields extends StatefulWidget {
  const _ExerciseFields({
    super.key,
    required this.index,
    required this.draft,
    required this.viewModel,
  });

  final int index;
  final ExerciseDraft draft;
  final InlineComposerViewModel viewModel;

  @override
  State<_ExerciseFields> createState() => _ExerciseFieldsState();
}

class _ExerciseFieldsState extends State<_ExerciseFields> {
  InlineComposerViewModel get vm => widget.viewModel;
  ExerciseDraft get e => widget.draft;
  late final _name = TextEditingController(text: e.name);
  late final _sets = TextEditingController(text: e.sets);
  late final _reps = TextEditingController(text: e.reps);
  late final _weight = TextEditingController(text: e.weight);

  @override
  void initState() {
    super.initState();
    _name.addListener(() => vm.updateExercise(e, name: _name.text));
    _sets.addListener(() => vm.updateExercise(e, sets: _sets.text));
    _reps.addListener(() => vm.updateExercise(e, reps: _reps.text));
    _weight.addListener(() => vm.updateExercise(e, weight: _weight.text));
  }

  @override
  void dispose() {
    for (final c in [_name, _sets, _reps, _weight]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration hint(String text) =>
        InputDecoration(isDense: true, hintText: text, counterText: '');
    return ExerciseCard(
      index: widget.index,
      onRemove: () => vm.removeExercise(e),
      name: TextField(
        controller: _name,
        maxLength: WorkoutExercise.maxNameLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: hint(ExerciseHints.name),
      ),
      sets: TextField(
        controller: _sets,
        keyboardType: TextInputType.number,
        decoration: hint(ExerciseHints.sets),
      ),
      reps: TextField(
        controller: _reps,
        keyboardType: TextInputType.number,
        decoration: hint(ExerciseHints.reps),
      ),
      weight: TextField(
        controller: _weight,
        maxLength: WorkoutExercise.maxWeightLength,
        decoration: hint(ExerciseHints.weight),
      ),
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
          iconSize: 14,
          onPressed: onRemove,
          icon: const Icon(Icons.close),
        ),
      ),
    ],
  );
}
