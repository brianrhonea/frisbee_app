import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/roster_player.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/app_segmented_button.dart';
import '../../core/ui/layout.dart';

/// Add/edit a roster player; pops with the updated player or null.
class PlayerDialog extends StatefulWidget {
  const PlayerDialog({
    super.key,
    this.initial,
    this.members = const {},
    this.linkedElsewhere = const {},
  });

  /// The player to edit, or a new one filled in (an empty id).
  final RosterPlayer? initial;

  /// Team members (uid → name) the player can be linked to, so their stats
  /// count on that member's profile. Empty hides the choice.
  final Map<String, String> members;

  /// Members already linked to another roster spot.
  final Set<String> linkedElsewhere;

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
  late String? _userId = widget.initial?.userId;

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    super.dispose();
  }

  /// A member picked (or null for none): their name fills the Name field.
  void _pickMember(String? uid) {
    setState(() {
      _userId = uid;
      if (uid != null) _name.text = widget.members[uid] ?? _name.text;
    });
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
        userId: _userId,
        paid: _paid,
        line: widget.initial?.line,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // A filled-in new spot (e.g. adding yourself) has no id yet.
      title: Text(
        (widget.initial?.id ?? '').isEmpty ? 'Add player' : 'Edit player',
      ),
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
              AppSegmentedButton<PlayerPosition>(
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
                subtitle: const Text('Dues or fees received'),
              ),
              if (widget.members.isNotEmpty) ...[
                const SizedBox(height: 8),
                _LinkPicker(
                  key: const ValueKey('link-to-member'),
                  linkedName: widget.members[_userId],
                  available: {
                    for (final e in widget.members.entries)
                      if (!widget.linkedElsewhere.contains(e.key))
                        e.key: e.value,
                  },
                  onPick: _pickMember,
                ),
              ],
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

/// "Link to a member": the member this roster spot is, whose stats then show
/// on their profile. Opens a list of the team's members who aren't linked to
/// a spot yet; picking one fills the player's name.
class _LinkPicker extends StatelessWidget {
  const _LinkPicker({
    super.key,
    required this.linkedName,
    required this.available,
    required this.onPick,
  });

  final String? linkedName;

  /// Members (uid to name) with no spot yet, or this spot's own member.
  final Map<String, String> available;
  final ValueChanged<String?> onPick;

  Future<void> _open(BuildContext context) async {
    final c = AppColors.of(context);
    final picked = await showModalBottomSheet<({String? uid})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      sheetAnimationStyle: AppMotion.sheetStyle(context),
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg,
                  0,
                  AppSpace.lg,
                  AppSpace.sm,
                ),
                child: Text(
                  'Link to a member',
                  style: AppText.section.copyWith(color: c.ink),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (linkedName != null)
                      ListTile(
                        minVerticalPadding: 12,
                        leading: const Icon(Icons.link_off),
                        title: const Text('Not linked'),
                        onTap: () => Navigator.pop(context, (uid: null)),
                      ),
                    if (available.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(AppSpace.lg),
                        child: Text(
                          'Every member is already linked to a spot.',
                          style: AppText.secondary.copyWith(color: c.muted),
                        ),
                      ),
                    for (final e in available.entries)
                      ListTile(
                        minVerticalPadding: 12,
                        leading: PersonAvatar(name: e.value, radius: 18),
                        title: Text(e.value),
                        trailing: e.value == linkedName
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.pop(context, (uid: e.key)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) onPick(picked.uid);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 8,
      leading: Icon(Icons.link, color: c.muted),
      title: Text(linkedName ?? 'Link to a member'),
      subtitle: Text(
        linkedName == null
            ? "Pick a member; their stats show on their profile"
            : "Linked: their stats show on this member's profile",
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _open(context),
    );
  }
}
