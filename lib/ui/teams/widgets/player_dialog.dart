import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/roster_player.dart';

/// Add/edit a roster player; pops with the updated player or null.
class PlayerDialog extends StatefulWidget {
  const PlayerDialog({super.key, this.initial});

  final RosterPlayer? initial;

  @override
  State<PlayerDialog> createState() => _PlayerDialogState();
}

class _PlayerDialogState extends State<PlayerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _number = TextEditingController(
    text: widget.initial?.number?.toString(),
  );
  late PlayerPosition _position =
      widget.initial?.position ?? PlayerPosition.hybrid;
  late bool _paid = widget.initial?.paid ?? false;

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      RosterPlayer(
        id: widget.initial?.id ?? '',
        name: _name.text.trim(),
        number: int.tryParse(_number.text),
        position: _position,
        userId: widget.initial?.userId,
        onUsau: widget.initial?.onUsau,
        paid: _paid,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add player' : 'Edit player'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _number,
                decoration: const InputDecoration(labelText: 'Jersey number'),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<PlayerPosition>(
                segments: [
                  for (final p in PlayerPosition.values)
                    ButtonSegment(value: p, label: Text(p.label)),
                ],
                selected: {_position},
                onSelectionChanged: (s) => setState(() => _position = s.first),
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _paid,
                onChanged: (v) => setState(() => _paid = v ?? false),
                title: const Text('Paid'),
                subtitle: const Text('Dues or USA Ultimate fees received'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
