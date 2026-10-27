import 'package:flutter/material.dart';

/// Asks for an invite code; pops with the entered code or null.
class JoinTeamDialog extends StatefulWidget {
  const JoinTeamDialog({super.key});

  @override
  State<JoinTeamDialog> createState() => _JoinTeamDialogState();
}

class _JoinTeamDialogState extends State<JoinTeamDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _code.text.trim();
    if (code.isNotEmpty) Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Join a team'),
    content: TextField(
      controller: _code,
      autofocus: true,
      textCapitalization: TextCapitalization.characters,
      decoration: const InputDecoration(
        labelText: 'Invite code',
        hintText: 'e.g. K7Q2XM',
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Join')),
    ],
  );
}
