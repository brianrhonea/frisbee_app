import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/models/chat.dart';
import '../../../domain/models/recurrence.dart';
import '../../../domain/models/team_event.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import 'package:provider/provider.dart';

import '../../core/themes/theme.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/overlay_panel.dart';
import '../../core/ui/scoreboard.dart' show TeamDot;
import '../../core/ui/status_views.dart';
import '../../core/ui/view_model_host.dart';
import '../../../data/repositories/calendar/calendar_repository.dart';
import '../../../data/repositories/user_post/user_post_repository.dart';
import '../view_models/event_editor_viewmodel.dart';
import '../../core/ui/time_picker.dart';
import '../../../data/repositories/profile/profile_repository.dart';
import 'new_shared_calendar_sheet.dart';
import 'schedule_widgets.dart' show RepeatNote, askSeriesScope;

/// Opens the event editor over the current page, like the post composer:
/// a card on wide screens, a bottom sheet on phones. Adds an event to
/// [teamId]'s schedule (or the user's own), starting on [day]. When it's
/// created, says so with a View button that opens it. Completes with the
/// new event's id, or null if the user closed it.
Future<String?> showEventEditor(
  BuildContext context, {
  String? teamId,
  DateTime? day,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final router = GoRouter.of(context);
  final created = await showOverlayPanel<_Created>(
    context,
    builder: (_, fit) => ViewModelHost(
      create: (c) => EventEditorViewModel(
        teamId: teamId,
        eventId: null,
        initialDay: day,
        eventRepository: c.read(),
        teamRepository: c.read(),
        authRepository: c.read(),
        postRepository: c.read<UserPostRepository?>(),
        calendarRepository: c.read<CalendarRepository?>(),
        profileRepository: readOptional<ProfileRepository>(c),
      ),
      builder: (_, vm) =>
          EventEditorScreen(viewModel: vm, inPanel: true, fitContent: fit),
    ),
  );
  if (created == null) return null;
  // Events on other calendars have no page of their own.
  final detail = switch ((created.teamId, created.calendarId)) {
    (final t?, _) => Routes.event(t, created.id),
    (_, null) => Routes.myEvent(created.id),
    _ => null,
  };
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(_createdMessage(created.shared)),
        action: detail == null
            ? null
            : SnackBarAction(
                label: 'View',
                onPressed: () => router.push(detail),
              ),
      ),
    );
  return created.id;
}

/// What the panel closes with when an event is created.
typedef _Created = ({
  String id,
  String? teamId,
  String? calendarId,
  bool? shared,
});

/// [shared]: posted for followers (true), asked to but couldn't (false), or
/// not asked (null).
String _createdMessage(bool? shared) => switch (shared) {
  true => 'Event created and shared with your followers',
  false => "Event created, but it couldn't be shared. Try posting it.",
  null => 'Event created',
};

/// Creates or edits an event: on a page of its own (from a link), or in a
/// panel over the page ([inPanel], see [showEventEditor]).
class EventEditorScreen extends StatefulWidget {
  const EventEditorScreen({
    super.key,
    required this.viewModel,
    this.inPanel = false,
    this.fitContent = false,
  });

  final EventEditorViewModel viewModel;

  /// Shown by [showEventEditor]: closes when saved instead of going to the
  /// event, and asks before throwing away changes.
  final bool inPanel;

  /// In the wide-screen card: only as tall as the form.
  final bool fitContent;

  @override
  State<EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends State<EventEditorScreen> {
  EventEditorViewModel get vm => widget.viewModel;

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

  /// Whether the user has changed anything since the editor opened.
  bool _changed = false;

  /// Closes the panel, first asking to discard any changes.
  Future<void> _close() async {
    final nav = Navigator.of(context);
    if (_changed &&
        !await confirmDialog(
          context,
          title: vm.isNew ? 'Discard this event?' : 'Discard your changes?',
          message: "What you've entered won't be saved.",
          confirmLabel: 'Discard',
          destructive: true,
        )) {
      return;
    }
    if (mounted) nav.pop();
  }

  void _onSave() {
    final cmd = vm.save;
    switch (cmd.result) {
      case Ok<String>(:final value) when widget.inPanel:
        cmd.clearResult();
        // The opener says it's done and offers to open it.
        final _Created created = (
          id: value,
          teamId: vm.teamId,
          calendarId: vm.calendarId,
          shared: vm.shared ? true : (vm.shareFailed ? false : null),
        );
        Navigator.of(context).pop(created);
      case Ok<String>(:final value):
        cmd.clearResult();
        showSnackBar(
          context,
          vm.isNew
              ? _createdMessage(
                  vm.shared ? true : (vm.shareFailed ? false : null),
                )
              : 'Event saved',
        );
        final teamId = vm.teamId;
        if (vm.calendarId != null) {
          // No page of its own: back to the schedule.
          context.canPop() ? context.pop(true) : context.go(Routes.schedule);
          return;
        }
        final detail = teamId == null
            ? Routes.myEvent(value)
            : Routes.event(teamId, value);
        if (!context.canPop()) {
          context.go(detail);
        } else if (vm.isNew) {
          // Swap the editor for the new event, so back returns to where
          // "New event" was tapped.
          context.pushReplacement(detail);
        } else {
          // Back to the event page that opened the editor.
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
    listenable: Listenable.merge([vm, vm.load, vm.save]),
    builder: (context, _) {
      final title = vm.isNew ? 'New event' : 'Edit event';
      Widget body(bool fit) {
        if (vm.load.running) {
          return PanelFrame.status(fit, const LoadingView());
        }
        if (vm.load.error) {
          return PanelFrame.status(
            fit,
            ErrorView(error: vm.load.result, onRetry: vm.load.execute),
          );
        }
        final form = _EventForm(
          initial: vm.initial,
          saving: vm.save.running,
          submitLabel: vm.isNew ? 'Create event' : 'Save',
          allowPoll: !vm.isPersonal,
          allowPublic: !vm.isPrivateGroup,
          audienceChoices: vm.audienceChoices,
          types: vm.types,
          schedulePicker: vm.canChooseSchedule
              ? _SchedulePicker(viewModel: vm)
              : null,
          allowShare: vm.canShare,
          allowRepeat: vm.isNew,
          onSubmit: (event, share, repeat) async {
            var scope = SeriesScope.one;
            if (vm.isSeries) {
              // One of a repeating series: this one, or it and later ones.
              final picked = await askSeriesScope(
                context,
                title: 'Save changes to "${event.title}"?',
                action: 'Save',
              );
              if (picked == null) return;
              scope = picked;
            }
            vm.shareWith(share);
            vm.repeatWith(repeat);
            vm.saveScope(scope);
            vm.save.execute(event);
          },
          shrinkWrap: fit,
          onChanged: () => _changed = true,
        );
        if (fit) return form;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: form,
          ),
        );
      }

      if (!widget.inPanel) {
        return Scaffold(
          appBar: AppBar(
            leading: backOr(context, Routes.home),
            title: Text(title),
          ),
          body: body(false),
        );
      }
      return PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: PanelFrame(
          fitContent: widget.fitContent,
          close: IconButton(
            tooltip: 'Close',
            onPressed: _close,
            icon: const Icon(Icons.close),
          ),
          title: title,
          body: body,
        ),
      );
    },
  );
}

class _EventForm extends StatefulWidget {
  const _EventForm({
    required this.initial,
    required this.saving,
    required this.submitLabel,
    required this.onSubmit,
    required this.types,
    this.allowPoll = true,
    this.allowPublic = true,
    this.audienceChoices = const {},
    this.schedulePicker,
    this.allowShare = false,
    this.allowRepeat = false,
    this.shrinkWrap = false,
    this.onChanged,
  });

  /// Offer to post the new event for the user's followers.
  final bool allowShare;

  /// Offer Repeat (new events only; a series can't change how it repeats).
  final bool allowRepeat;

  /// Only as tall as the fields (in the wide-screen panel).
  final bool shrinkWrap;

  /// Called whenever the user changes something.
  final VoidCallback? onChanged;

  /// Offer the Public switch; a private group's events are members-only.
  final bool allowPublic;

  /// Types to choose from; groups and teams offer different ones.
  final List<EventType> types;

  final TeamEvent initial;
  final bool saving;
  final String submitLabel;

  /// The event, the message to share it with (null not to), and how it
  /// repeats (null for a one-off).
  final void Function(TeamEvent event, String? share, Repeat? repeat) onSubmit;

  /// Polls, and showing the event on the public team page, are for team
  /// events only.
  final bool allowPoll;

  /// Shown above the title when the event can go on more than one schedule.
  final Widget? schedulePicker;

  /// For a school or club community's event: who it can be shown to,
  /// id → label (everyone, then roles). Empty elsewhere.
  final Map<String, String> audienceChoices;

  @override
  State<_EventForm> createState() => _EventFormState();
}

typedef _OptionField = ({String id, TextEditingController text});

class _EventFormState extends State<_EventForm> {
  static const _uuid = Uuid();
  static const _maxOptions = 10;

  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initial.title);
  late final _location = TextEditingController(text: widget.initial.location);
  late final _notes = TextEditingController(text: widget.initial.notes);
  late EventType _picked = widget.initial.type;

  /// The picked type, or the schedule's first one when the picked type
  /// isn't offered there (e.g. Practice after switching to a group).
  EventType get _type =>
      widget.types.contains(_picked) ? _picked : widget.types.first;
  late DateTime _day = DateUtils.dateOnly(widget.initial.startsAt);
  late TimeOfDay _start = TimeOfDay.fromDateTime(widget.initial.startsAt);
  late TimeOfDay? _end = widget.initial.endsAt == null
      ? null
      : TimeOfDay.fromDateTime(widget.initial.endsAt!);

  /// How a new event repeats; null for a one-off.
  RepeatFrequency? _freq;
  DateTime? _until;

  /// The last day a repeat can fall on: picked, or 7 weeks after the
  /// first (8 weekly events).
  DateTime get _repeatUntil =>
      _until ?? DateTime(_day.year, _day.month, _day.day + 49);

  Repeat? get _repeat =>
      _freq == null ? null : Repeat(freq: _freq!, until: _repeatUntil);

  late bool _public = widget.initial.isPublic;
  late Set<String> _audience = widget.initial.audience.isEmpty
      ? {ChatAudience.everyone}
      : {...widget.initial.audience};
  bool _share = false;
  final _shareMessage = TextEditingController();
  late bool _hasPoll = widget.initial.poll != null;
  late final _question = TextEditingController(
    text: widget.initial.poll?.question ?? '',
  );
  late bool _multiple = widget.initial.poll?.multiple ?? false;
  late final List<_OptionField> _options = [
    for (final o in widget.initial.poll?.options ?? const <PollOption>[])
      (id: o.id, text: TextEditingController(text: o.text)),
  ];

  // Every setState here is the user changing something.
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    widget.onChanged?.call();
  }

  @override
  void dispose() {
    for (final c in [_title, _location, _notes, _question, _shareMessage]) {
      c.dispose();
    }
    for (final o in _options) {
      o.text.dispose();
    }
    super.dispose();
  }

  void _addOption() => setState(
    () => _options.add((id: _uuid.v4(), text: TextEditingController())),
  );

  void _removeOption(int i) =>
      setState(() => _options.removeAt(i).text.dispose());

  void _togglePoll(bool on) => setState(() {
    _hasPoll = on;
    while (on && _options.length < 2) {
      _options.add((id: _uuid.v4(), text: TextEditingController()));
    }
  });

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _pickStart() async {
    final picked = await showTypedTimePicker(
      context: context,
      initialTime: _start,
    );
    if (picked != null) setState(() => _start = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showTypedTimePicker(
      context: context,
      initialTime:
          _end ??
          TimeOfDay(hour: (_start.hour + 2) % 24, minute: _start.minute),
    );
    if (picked != null) setState(() => _end = picked);
  }

  Future<void> _pickUntil() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _repeatUntil.isBefore(_day) ? _day : _repeatUntil,
      firstDate: _day,
      lastDate: DateTime(_day.year + 1, _day.month, _day.day),
      helpText: 'Repeat until',
    );
    if (picked != null) setState(() => _until = picked);
  }

  DateTime _at(TimeOfDay t) =>
      DateTime(_day.year, _day.month, _day.day, t.hour, t.minute);

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final repeat = widget.allowRepeat ? _repeat : null;
    if (repeat != null && repeatProblem(_day, repeat) != null) return;
    final startsAt = _at(_start);
    var endsAt = _end == null ? null : _at(_end!);
    // An end time before the start means the event runs past midnight.
    if (endsAt != null && endsAt.isBefore(startsAt)) {
      endsAt = endsAt.add(const Duration(days: 1));
    }
    final options = [
      for (final o in _options)
        if (o.text.text.trim().isNotEmpty)
          PollOption(id: o.id, text: o.text.text.trim()),
    ];
    widget.onSubmit(
      widget.initial.copyWith(
        title: _title.text.trim(),
        type: _type,
        startsAt: startsAt,
        endsAt: () => endsAt,
        location: _location.text.trim(),
        notes: _notes.text.trim(),
        isPublic: _public && widget.allowPoll && widget.allowPublic,
        audience: widget.audienceChoices.isEmpty ? const {} : _audience,
        poll: () => _hasPoll && widget.allowPoll
            ? EventPoll(
                question: _question.text.trim(),
                options: options,
                multiple: _multiple,
              )
            : null,
      ),
      _share && widget.allowShare ? _shareMessage.text.trim() : null,
      repeat,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    return Form(
      key: _formKey,
      onChanged: widget.onChanged,
      child: ListView(
        shrinkWrap: widget.shrinkWrap,
        padding: EdgeInsets.all(widget.shrinkWrap ? 20 : 16),
        children: [
          if (widget.schedulePicker case final picker?) ...[
            picker,
            const SizedBox(height: 16),
          ],
          const FieldLabel('Type'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in widget.types)
                ChoiceChip(
                  showCheckmark: false,
                  label: Text(t.label),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _picked = t),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _title,
            autofocus: widget.initial.isNew,
            maxLength: 100,
            decoration: const InputDecoration(labelText: 'Title'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Enter a title' : null,
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, c) {
              final date = PickerField(
                label: 'Date',
                icon: Icons.calendar_today_outlined,
                value: DateFormat.yMMMEd().format(_day),
                onTap: _pickDay,
              );
              final times = Row(
                children: [
                  Expanded(
                    child: PickerField(
                      label: 'Starts',
                      icon: Icons.schedule,
                      value: loc.formatTimeOfDay(_start),
                      onTap: _pickStart,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PickerField(
                      label: 'Ends',
                      icon: Icons.schedule_outlined,
                      value: _end == null
                          ? 'Optional'
                          : loc.formatTimeOfDay(_end!),
                      onTap: _pickEnd,
                      onClear: _end == null
                          ? null
                          : () => setState(() => _end = null),
                    ),
                  ),
                ],
              );
              if (c.maxWidth < 520) {
                return Column(
                  children: [date, const SizedBox(height: 12), times],
                );
              }
              return Row(
                children: [
                  Expanded(child: date),
                  const SizedBox(width: 12),
                  Expanded(child: times),
                ],
              );
            },
          ),
          if (widget.allowRepeat) ...[
            const SizedBox(height: 12),
            _RepeatFields(
              day: _day,
              freq: _freq,
              until: _repeatUntil,
              onFreq: (f) => setState(() => _freq = f),
              onPickUntil: _pickUntil,
            ),
          ] else if (widget.initial.series case final series?) ...[
            const SizedBox(height: 12),
            RepeatNote(series: series),
          ],
          const SizedBox(height: 16),
          TextFormField(
            controller: _location,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Location',
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _notes,
            minLines: 2,
            maxLines: 6,
            maxLength: 5000,
            decoration: const InputDecoration(
              labelText: 'Notes',
              hintText: 'What to bring, dark/light jerseys, carpools…',
              alignLabelWithHint: true,
            ),
          ),
          if (widget.audienceChoices.isNotEmpty) ...[
            const SizedBox(height: 16),
            _AudiencePicker(
              choices: widget.audienceChoices,
              picked: _audience,
              onChanged: (a) => setState(() => _audience = a),
            ),
          ],
          if (widget.allowPoll) ...[
            const SizedBox(height: 16),
            SettingsCard(
              children: [
                if (widget.allowPublic)
                  SwitchListTile(
                    secondary: const Icon(Icons.public),
                    title: const Text('Public'),
                    subtitle: Text(
                      _public
                          ? 'Shown on the team page to anyone who finds the team. '
                                'RSVPs and polls stay private.'
                          : 'Only team members can see it',
                    ),
                    value: _public,
                    onChanged: (v) => setState(() => _public = v),
                  ),
                SwitchListTile(
                  secondary: const Icon(Icons.poll_outlined),
                  title: const Text('Add a poll'),
                  subtitle: const Text(
                    'e.g. "Who can drive?" or "Pick a jersey"',
                  ),
                  value: _hasPoll,
                  onChanged: _togglePoll,
                ),
              ],
            ),
            if (_hasPoll) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _question,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Question'),
                validator: (v) => _hasPoll && (v == null || v.trim().isEmpty)
                    ? 'Enter a question'
                    : null,
              ),
              for (var i = 0; i < _options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextFormField(
                    key: ValueKey(_options[i].id),
                    controller: _options[i].text,
                    maxLength: 100,
                    decoration: InputDecoration(
                      labelText: 'Option ${i + 1}',
                      counterText: '',
                      suffixIcon: _options.length > 2
                          ? IconButton(
                              tooltip: 'Remove option',
                              icon: const Icon(Icons.close),
                              onPressed: () => _removeOption(i),
                            )
                          : null,
                    ),
                    validator: (_) {
                      if (!_hasPoll || i > 0) return null;
                      final filled = _options
                          .where((o) => o.text.text.trim().isNotEmpty)
                          .length;
                      return filled < 2 ? 'Add at least two options' : null;
                    },
                  ),
                ),
              if (_options.length < _maxOptions)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addOption,
                    icon: const Icon(Icons.add),
                    label: const Text('Add option'),
                  ),
                ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: const Text('Allow multiple choices'),
                value: _multiple,
                onChanged: (v) => setState(() => _multiple = v),
              ),
              if (!widget.initial.isNew && widget.initial.poll != null)
                Text(
                  'Changing the options resets existing votes.',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ],
          if (widget.allowShare) ...[
            const SizedBox(height: 16),
            SettingsCard(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.campaign_outlined),
                  title: const Text('Share with followers'),
                  subtitle: Text(
                    widget.allowPoll
                        ? 'Posts it on your profile, so the people who follow '
                              "you and the team's members see it in their feed. "
                              'RSVPs and notes stay here.'
                        : 'Posts it on your profile, so the people who follow '
                              'you see it in their feed. RSVPs and notes stay '
                              'here.',
                  ),
                  value: _share,
                  onChanged: (v) => setState(() => _share = v),
                ),
              ],
            ),
            if (_share) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _shareMessage,
                minLines: 1,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Say something (optional)',
                  hintText: 'Come out and play!',
                ),
              ),
            ],
          ],
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: widget.saving ? null : _submit,
            child: widget.saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.submitLabel),
          ),
        ],
      ),
    );
  }
}

/// A form field that opens a date or time picker when tapped.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final IconData icon;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(4),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: onClear == null
            ? null
            : IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClear,
              ),
      ),
      child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
  );
}

/// Which schedule a new event goes on: personal, or a team the user may
/// edit.
class _SchedulePicker extends StatelessWidget {
  const _SchedulePicker({required this.viewModel});

  final EventEditorViewModel viewModel;

  Future<void> _newCalendar(BuildContext context) async {
    final made = await showNewSharedCalendarSheet(
      context,
      search: viewModel.searchPeople,
    );
    if (made == null) return;
    await viewModel.createCalendar.execute(made);
    final cmd = viewModel.createCalendar;
    if (cmd.error && context.mounted) showErrorSnackBar(context, cmd.result);
    cmd.clearResult();
  }

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Add to'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              showCheckmark: false,
              avatar: TeamDot(color: c.personal),
              label: const Text('My calendar'),
              selected: vm.isMyCalendar,
              onSelected: (_) => vm.setSchedule(null),
            ),
            for (final cal in vm.editableCalendars)
              ChoiceChip(
                showCheckmark: false,
                avatar: TeamDot(color: cal.color.color),
                label: Text(cal.label),
                selected: vm.calendarId == cal.id,
                onSelected: (_) => vm.setCalendar(cal.id),
              ),
            for (final t in vm.editableTeams)
              ChoiceChip(
                showCheckmark: false,
                avatar: TeamDot(color: c.team),
                label: Text(t.name),
                selected: vm.teamId == t.id,
                onSelected: (_) => vm.setSchedule(t.id),
              ),
            // Share it with people without setting up a calendar first.
            if (vm.canCreateCalendar)
              ListenableBuilder(
                listenable: vm.createCalendar,
                builder: (context, _) => ActionChip(
                  avatar: vm.createCalendar.running
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add_alt_outlined, size: 18),
                  label: const Text('New shared calendar'),
                  onPressed: vm.createCalendar.running
                      ? null
                      : () => _newCalendar(context),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          vm.isPersonal
              ? (vm.scheduleCalendar?.isShared ?? false)
                    ? 'Everyone on ${vm.scheduleCalendar!.name} sees it; '
                          "people who can only view don't see notes."
                    : 'Only you will see this event.'
              : vm.isOrganization
              ? 'Choose below who in the community sees it and can RSVP.'
              : vm.isCommunity
              ? 'Everyone in the community will see this event and can RSVP.'
              : 'Everyone on the team will see this event and can RSVP.',
          style: TextStyle(fontSize: 12, color: c.muted),
        ),
      ],
    );
  }
}

/// Who sees a school or club community's event: everyone, or members with
/// any of the picked roles. Picking a role drops everyone, and the last
/// role off brings it back, so the event always has an audience.
class _AudiencePicker extends StatelessWidget {
  const _AudiencePicker({
    required this.choices,
    required this.picked,
    required this.onChanged,
  });

  final Map<String, String> choices;
  final Set<String> picked;
  final ValueChanged<Set<String>> onChanged;

  void _toggle(String id, bool on) {
    const everyone = ChatAudience.everyone;
    if (id == everyone) return onChanged(const {everyone});
    final next = {...picked}..remove(everyone);
    on ? next.add(id) : next.remove(id);
    onChanged(next.isEmpty ? const {everyone} : next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Who sees it'),
        Text(
          'Admins who manage events always see it.',
          style: TextStyle(fontSize: 12, color: AppColors.of(context).muted),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final e in choices.entries)
              FilterChip(
                label: Text(e.value),
                selected: picked.contains(e.key),
                onSelected: (on) => _toggle(e.key, on),
              ),
          ],
        ),
      ],
    );
  }
}

/// A small label above a group of form controls, e.g. "Type".
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.of(context).ink2,
      ),
    ),
  );
}

/// Switches and other settings in a card, one per row with a line between.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTileTheme(
      data: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            children[i],
          ],
        ],
      ),
    ),
  );
}

/// Repeat for a new event: does not repeat, daily, weekly on its weekday,
/// every 2 weeks or monthly on its day, until an end date, with how many
/// events that makes (or why it can't be saved).
class _RepeatFields extends StatelessWidget {
  const _RepeatFields({
    required this.day,
    required this.freq,
    required this.until,
    required this.onFreq,
    required this.onPickUntil,
  });

  final DateTime day;
  final RepeatFrequency? freq;
  final DateTime until;
  final ValueChanged<RepeatFrequency?> onFreq;
  final VoidCallback onPickUntil;

  String _label(RepeatFrequency? f) {
    final weekday = DateFormat.EEEE().format(day);
    return switch (f) {
      null => 'Does not repeat',
      RepeatFrequency.daily => 'Daily',
      RepeatFrequency.weekly => 'Weekly on $weekday',
      RepeatFrequency.biweekly => 'Every 2 weeks on $weekday',
      RepeatFrequency.monthly => 'Monthly on day ${day.day}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final repeat = freq == null ? null : Repeat(freq: freq!, until: until);
    final problem = repeat == null ? null : repeatProblem(day, repeat);
    final count = repeat == null ? 0 : repeatDates(day, repeat).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<RepeatFrequency?>(
          key: const ValueKey('repeat'),
          initialValue: freq,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Repeat',
            prefixIcon: Icon(Icons.repeat),
          ),
          items: [
            for (final f in <RepeatFrequency?>[null, ...RepeatFrequency.values])
              DropdownMenuItem(
                value: f,
                child: Text(_label(f), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onFreq,
        ),
        if (repeat != null) ...[
          const SizedBox(height: 12),
          PickerField(
            label: 'Ends on',
            icon: Icons.event_outlined,
            value: DateFormat.yMMMEd().format(until),
            onTap: onPickUntil,
          ),
          const SizedBox(height: 6),
          Text(
            problem ?? 'Creates $count events',
            style: TextStyle(
              fontSize: 13,
              color: problem == null
                  ? c.muted
                  : Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}
