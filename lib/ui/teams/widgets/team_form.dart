import 'package:flutter/material.dart';

import '../../../domain/models/team.dart';
import '../../groups/widgets/location_picker_dialog.dart';

/// Fields shared by create and edit. Teams have name, division, level and
/// city; community groups have name, city, description, a location and
/// whether joining needs approval.
class TeamForm extends StatefulWidget {
  const TeamForm({
    super.key,
    required this.onSubmit,
    required this.submitLabel,
    this.initial,
    this.kind = TeamKind.team,
    this.busy = false,
  });

  final NewTeam? initial;

  /// Used when [initial] is null; otherwise the initial's kind wins.
  final TeamKind kind;
  final ValueChanged<NewTeam> onSubmit;
  final String submitLabel;
  final bool busy;

  @override
  State<TeamForm> createState() => _TeamFormState();
}

class _TeamFormState extends State<TeamForm> {
  final _formKey = GlobalKey<FormState>();
  late final TeamKind _kind = widget.initial?.kind ?? widget.kind;
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _city = TextEditingController(text: widget.initial?.city);
  late final _description = TextEditingController(
    text: widget.initial?.description,
  );
  late Division _division = widget.initial?.division ?? Division.mixed;
  late CompetitionLevel _level =
      widget.initial?.level ??
      (_isGroup ? CompetitionLevel.pickup : CompetitionLevel.club);
  late bool _requiresApproval = widget.initial?.requiresApproval ?? false;
  late GroupLocation? _location = widget.initial?.location;

  bool get _isGroup => _kind == TeamKind.community;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final picked = await pickGroupLocation(context, initial: _location);
    if (picked != null) setState(() => _location = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    widget.onSubmit(
      NewTeam(
        name: _name.text.trim(),
        division: _division,
        level: _level,
        city: _city.text.trim(),
        kind: _kind,
        description: _isGroup ? _description.text.trim() : '',
        requiresApproval: _isGroup && _requiresApproval,
        location: _isGroup ? _location : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final noun = _isGroup ? 'group' : 'team';
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _name,
            decoration: InputDecoration(
              labelText: _isGroup ? 'Group name' : 'Team name',
            ),
            textCapitalization: TextCapitalization.words,
            maxLength: 80,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter a $noun name' : null,
          ),
          const SizedBox(height: 8),
          if (_isGroup) ...[
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'About the group (optional)',
                hintText: 'When and where you play, skill level, what to bring',
              ),
              minLines: 2,
              maxLines: 5,
              maxLength: 1000,
            ),
            const SizedBox(height: 8),
          ] else ...[
            DropdownButtonFormField<Division>(
              initialValue: _division,
              decoration: const InputDecoration(labelText: 'Division'),
              items: [
                for (final d in Division.values)
                  DropdownMenuItem(value: d, child: Text(d.label)),
              ],
              onChanged: (v) => setState(() => _division = v!),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<CompetitionLevel>(
              initialValue: _level,
              decoration: const InputDecoration(labelText: 'Level'),
              items: [
                for (final l in CompetitionLevel.values)
                  DropdownMenuItem(value: l, child: Text(l.label)),
              ],
              onChanged: (v) => setState(() => _level = v!),
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: _city,
            decoration: const InputDecoration(labelText: 'City (optional)'),
            textCapitalization: TextCapitalization.words,
          ),
          if (_isGroup) ...[
            const SizedBox(height: 16),
            _LocationField(
              location: _location,
              onPick: _pickLocation,
              onClear: () => setState(() => _location = null),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Approve new members'),
              subtitle: Text(
                _requiresApproval
                    ? 'People ask to join; owners and organizers approve them.'
                    : 'Anyone can join from the group page.',
              ),
              value: _requiresApproval,
              onChanged: (v) => setState(() => _requiresApproval = v),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: widget.busy ? null : _submit,
            child: widget.busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.submitLabel),
          ),
        ],
      ),
    );
  }
}

class _LocationField extends StatelessWidget {
  const _LocationField({
    required this.location,
    required this.onPick,
    required this.onClear,
  });

  final GroupLocation? location;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l = location;
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Location (optional)',
        helperText: 'Shown on a map on the group page',
      ),
      child: Row(
        children: [
          const Icon(Icons.place_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l == null
                  ? 'No location set'
                  : (l.address.isEmpty ? 'Pin on the map' : l.address),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onPick,
            child: Text(l == null ? 'Set' : 'Change'),
          ),
          if (l != null)
            IconButton(
              tooltip: 'Remove location',
              icon: const Icon(Icons.close),
              onPressed: onClear,
            ),
        ],
      ),
    );
  }
}
