import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/models/team_event.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/event_editor_viewmodel.dart';
import 'event_style.dart';

class EventEditorScreen extends StatefulWidget {
  const EventEditorScreen({super.key, required this.viewModel});

  final EventEditorViewModel viewModel;

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

  void _onSave() {
    final cmd = vm.save;
    switch (cmd.result) {
      case Ok<String>(:final value):
        cmd.clearResult();
        showSnackBar(context, vm.isNew ? 'Event created' : 'Event saved');
        final teamId = vm.teamId;
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
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        leading: backOr(context, Routes.home),
        title: Text(vm.isNew ? 'New event' : 'Edit event'),
      ),
      body: vm.load.running
          ? const LoadingView()
          : vm.load.error
          ? ErrorView(error: vm.load.result, onRetry: vm.load.execute)
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: _EventForm(
                  initial: vm.initial,
                  saving: vm.save.running,
                  submitLabel: vm.isNew ? 'Create event' : 'Save',
                  allowPoll: !vm.isPersonal,
                  schedulePicker: vm.canChooseSchedule
                      ? _SchedulePicker(viewModel: vm)
                      : null,
                  onSubmit: vm.save.execute,
                ),
              ),
            ),
    ),
  );
}

class _EventForm extends StatefulWidget {
  const _EventForm({
    required this.initial,
    required this.saving,
    required this.submitLabel,
    required this.onSubmit,
    this.allowPoll = true,
    this.schedulePicker,
  });

  final TeamEvent initial;
  final bool saving;
  final String submitLabel;
  final ValueChanged<TeamEvent> onSubmit;

  /// Polls, and showing the event on the public team page, are for team
  /// events only.
  final bool allowPoll;

  /// Shown above the title when the event can go on more than one schedule.
  final Widget? schedulePicker;

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
  late EventType _type = widget.initial.type;
  late DateTime _day = DateUtils.dateOnly(widget.initial.startsAt);
  late TimeOfDay _start = TimeOfDay.fromDateTime(widget.initial.startsAt);
  late TimeOfDay? _end = widget.initial.endsAt == null
      ? null
      : TimeOfDay.fromDateTime(widget.initial.endsAt!);

  late bool _public = widget.initial.isPublic;
  late bool _hasPoll = widget.initial.poll != null;
  late final _question = TextEditingController(
    text: widget.initial.poll?.question ?? '',
  );
  late bool _multiple = widget.initial.poll?.multiple ?? false;
  late final List<_OptionField> _options = [
    for (final o in widget.initial.poll?.options ?? const <PollOption>[])
      (id: o.id, text: TextEditingController(text: o.text)),
  ];

  @override
  void dispose() {
    for (final c in [_title, _location, _notes, _question]) {
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
    final picked = await showTimePicker(context: context, initialTime: _start);
    if (picked != null) setState(() => _start = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          _end ??
          TimeOfDay(hour: (_start.hour + 2) % 24, minute: _start.minute),
    );
    if (picked != null) setState(() => _end = picked);
  }

  DateTime _at(TimeOfDay t) =>
      DateTime(_day.year, _day.month, _day.day, t.hour, t.minute);

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
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
        isPublic: _public && widget.allowPoll,
        poll: () => _hasPoll && widget.allowPoll
            ? EventPoll(
                question: _question.text.trim(),
                options: options,
                multiple: _multiple,
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.schedulePicker case final picker?) ...[
            picker,
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: _title,
            autofocus: widget.initial.isNew,
            maxLength: 100,
            decoration: const InputDecoration(labelText: 'Title'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Enter a title' : null,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in EventType.values)
                ChoiceChip(
                  avatar: Icon(t.icon, size: 18),
                  label: Text(t.label),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              final date = _PickerField(
                label: 'Date',
                icon: Icons.calendar_today_outlined,
                value: DateFormat.yMMMEd().format(_day),
                onTap: _pickDay,
              );
              final times = Row(
                children: [
                  Expanded(
                    child: _PickerField(
                      label: 'Starts',
                      icon: Icons.schedule,
                      value: loc.formatTimeOfDay(_start),
                      onTap: _pickStart,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PickerField(
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
          if (widget.allowPoll) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
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
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.poll_outlined),
              title: const Text('Add a poll'),
              subtitle: const Text('e.g. "Who can drive?" or "Pick a jersey"'),
              value: _hasPoll,
              onChanged: _togglePoll,
            ),
            if (_hasPoll) ...[
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
                contentPadding: EdgeInsets.zero,
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
          const SizedBox(height: 24),
          FilledButton(
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

class _PickerField extends StatelessWidget {
  const _PickerField({
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

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Add to', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              avatar: const Icon(Icons.person_outline, size: 18),
              label: const Text('My schedule'),
              selected: vm.isPersonal,
              onSelected: (_) => vm.setSchedule(null),
            ),
            for (final t in vm.editableTeams)
              ChoiceChip(
                avatar: const Icon(Icons.groups_outlined, size: 18),
                label: Text(t.name),
                selected: vm.teamId == t.id,
                onSelected: (_) => vm.setSchedule(t.id),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          vm.isPersonal
              ? 'Only you will see this event.'
              : 'Everyone on the team will see this event and can RSVP.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
