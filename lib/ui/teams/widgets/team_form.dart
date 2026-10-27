import 'package:flutter/material.dart';

import '../../../domain/models/team.dart';

/// Name / division / level / city fields shared by create and edit.
class TeamForm extends StatefulWidget {
  const TeamForm({
    super.key,
    required this.onSubmit,
    required this.submitLabel,
    this.initial,
    this.busy = false,
  });

  final NewTeam? initial;
  final ValueChanged<NewTeam> onSubmit;
  final String submitLabel;
  final bool busy;

  @override
  State<TeamForm> createState() => _TeamFormState();
}

class _TeamFormState extends State<TeamForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _city = TextEditingController(text: widget.initial?.city);
  late Division _division = widget.initial?.division ?? Division.mixed;
  late CompetitionLevel _level = widget.initial?.level ?? CompetitionLevel.club;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    widget.onSubmit(
      NewTeam(
        name: _name.text.trim(),
        division: _division,
        level: _level,
        city: _city.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Team name'),
            textCapitalization: TextCapitalization.words,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter a team name' : null,
          ),
          const SizedBox(height: 16),
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
          TextFormField(
            controller: _city,
            decoration: const InputDecoration(labelText: 'City (optional)'),
            textCapitalization: TextCapitalization.words,
          ),
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
