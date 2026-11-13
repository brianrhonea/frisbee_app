import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/meeting.dart';
import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../schedule/widgets/event_editor_screen.dart' show PickerField;
import '../view_models/meeting_editor_viewmodel.dart';

class MeetingEditorScreen extends StatefulWidget {
  const MeetingEditorScreen({super.key, required this.viewModel});

  final MeetingEditorViewModel viewModel;

  @override
  State<MeetingEditorScreen> createState() => _MeetingEditorScreenState();
}

class _MeetingEditorScreenState extends State<MeetingEditorScreen> {
  MeetingEditorViewModel get vm => widget.viewModel;

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
        showSnackBar(context, vm.isNew ? 'Meeting scheduled' : 'Meeting saved');
        final detail = Routes.meeting(vm.teamId, value);
        if (!context.canPop()) {
          context.go(detail);
        } else if (vm.isNew) {
          context.pushReplacement(detail);
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
    listenable: Listenable.merge([vm, vm.load, vm.save]),
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        leading: backOr(context, Routes.teamEvents(vm.teamId)),
        title: Text(vm.isNew ? 'New meeting' : 'Edit meeting'),
      ),
      body: vm.load.running
          ? const LoadingView()
          : vm.load.error
          ? ErrorView(error: vm.load.result, onRetry: vm.load.execute)
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: _MeetingForm(
                  initial: vm.initial,
                  roles: vm.invitableRoles,
                  members: vm.invitableMembers,
                  saving: vm.save.running,
                  submitLabel: vm.isNew ? 'Schedule meeting' : 'Save',
                  onSubmit: vm.save.execute,
                ),
              ),
            ),
    ),
  );
}

class _MeetingForm extends StatefulWidget {
  const _MeetingForm({
    required this.initial,
    required this.roles,
    required this.members,
    required this.saving,
    required this.submitLabel,
    required this.onSubmit,
  });

  final TeamMeeting initial;
  final List<TeamRole> roles;
  final List<MeetingMember> members;
  final bool saving;
  final String submitLabel;
  final ValueChanged<TeamMeeting> onSubmit;

  @override
  State<_MeetingForm> createState() => _MeetingFormState();
}

class _MeetingFormState extends State<_MeetingForm> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initial.title);
  late final _notes = TextEditingController(text: widget.initial.notes);
  late DateTime _day = DateUtils.dateOnly(widget.initial.startsAt);
  late TimeOfDay _start = TimeOfDay.fromDateTime(widget.initial.startsAt);
  late TimeOfDay? _end = widget.initial.endsAt == null
      ? null
      : TimeOfDay.fromDateTime(widget.initial.endsAt!);
  late final Set<TeamRole> _roles = {...widget.initial.inviteRoles};
  late final Set<String> _users = {...widget.initial.inviteUsers};
  late bool _requireApproval = widget.initial.requireApproval;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

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
          TimeOfDay(hour: (_start.hour + 1) % 24, minute: _start.minute),
    );
    if (picked != null) setState(() => _end = picked);
  }

  DateTime _at(TimeOfDay t) =>
      DateTime(_day.year, _day.month, _day.day, t.hour, t.minute);

  void _toggleRole(TeamRole role, bool on) =>
      setState(() => on ? _roles.add(role) : _roles.remove(role));

  void _toggleUser(String uid, bool on) =>
      setState(() => on ? _users.add(uid) : _users.remove(uid));

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final startsAt = _at(_start);
    var endsAt = _end == null ? null : _at(_end!);
    if (endsAt != null && endsAt.isBefore(startsAt)) {
      endsAt = endsAt.add(const Duration(days: 1));
    }
    widget.onSubmit(
      widget.initial.copyWith(
        title: _title.text.trim(),
        startsAt: startsAt,
        endsAt: () => endsAt,
        notes: _notes.text.trim(),
        inviteRoles: _roles,
        inviteUsers: _users,
        requireApproval: _requireApproval,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    // People already invited by their role don't need picking.
    final pickable = [
      for (final m in widget.members)
        if (!_roles.contains(m.role)) m,
    ];
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _title,
            autofocus: widget.initial.isNew,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'e.g. Film review, Captains sync',
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Enter a title' : null,
          ),
          const SizedBox(height: 8),
          PickerField(
            label: 'Date',
            icon: Icons.calendar_today_outlined,
            value: DateFormat.yMMMEd().format(_day),
            onTap: _pickDay,
          ),
          const SizedBox(height: 12),
          Row(
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
                  value: _end == null ? 'Optional' : loc.formatTimeOfDay(_end!),
                  onTap: _pickEnd,
                  onClear: _end == null
                      ? null
                      : () => setState(() => _end = null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _notes,
            minLines: 2,
            maxLines: 6,
            maxLength: 5000,
            decoration: const InputDecoration(
              labelText: 'Agenda',
              alignLabelWithHint: true,
            ),
          ),
          const Divider(height: 32),
          Text('Who can see and join', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Owners, coaches and captains are always invited.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const FilterChip(
                label: Text('Admins'),
                selected: true,
                onSelected: null,
              ),
              for (final r in widget.roles)
                FilterChip(
                  label: Text('All ${r.pluralLabel.toLowerCase()}'),
                  selected: _roles.contains(r),
                  onSelected: (on) => _toggleRole(r, on),
                ),
            ],
          ),
          if (pickable.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Or pick people', style: theme.textTheme.labelLarge),
            for (final m in pickable)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(m.name),
                subtitle: Text(m.role.label),
                value: _users.contains(m.uid),
                onChanged: (on) => _toggleUser(m.uid, on ?? false),
              ),
          ],
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.how_to_reg_outlined),
            title: const Text('Require admin approval to join'),
            subtitle: Text(
              _requireApproval
                  ? 'Invitees wait in the lobby until an admin lets them in.'
                  : 'Invitees can join as soon as the meeting starts.',
            ),
            value: _requireApproval,
            onChanged: (v) => setState(() => _requireApproval = v),
          ),
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
