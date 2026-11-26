import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/chat.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/chat_room_settings_viewmodel.dart';

/// Creates a chat room or edits its name and access.
class ChatRoomSettingsScreen extends StatefulWidget {
  const ChatRoomSettingsScreen({super.key, required this.viewModel});

  final ChatRoomSettingsViewModel viewModel;

  @override
  State<ChatRoomSettingsScreen> createState() => _ChatRoomSettingsScreenState();
}

class _ChatRoomSettingsScreenState extends State<ChatRoomSettingsScreen> {
  ChatRoomSettingsViewModel get vm => widget.viewModel;
  TextEditingController? _name;

  @override
  void initState() {
    super.initState();
    vm.save.addListener(_onSave);
    vm.delete.addListener(_onDelete);
  }

  @override
  void dispose() {
    vm.save.removeListener(_onSave);
    vm.delete.removeListener(_onDelete);
    _name?.dispose();
    super.dispose();
  }

  void _onSave() {
    switch (vm.save.result) {
      case Ok(:final value):
        vm.save.clearResult();
        if (vm.isNew) {
          context.pushReplacement(Routes.chatRoom(vm.teamId, value));
        } else {
          context.pop();
        }
      case final Error<String> e:
        showErrorSnackBar(context, e);
        vm.save.clearResult();
      case null:
        break;
    }
  }

  void _onDelete() {
    if (vm.delete.completed) {
      vm.delete.clearResult();
      context.go(Routes.teamChat(vm.teamId));
    } else if (vm.delete.error) {
      showErrorSnackBar(context, vm.delete.result);
      vm.delete.clearResult();
    }
  }

  Future<void> _confirmDelete(ChatRoom room) async {
    if (await confirmDialog(
      context,
      title: 'Delete ${room.name}?',
      message: 'All of its messages, photos and files are deleted too.',
      confirmLabel: 'Delete',
      destructive: true,
    )) {
      vm.delete.execute();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([vm, vm.save, vm.delete]),
      builder: (context, _) {
        final room = vm.room;
        if (!vm.loaded) {
          return Scaffold(appBar: AppBar(), body: const LoadingView());
        }
        if (room == null || !vm.canManage) {
          return Scaffold(
            appBar: AppBar(),
            body: vm.error != null
                ? ErrorView(error: vm.error)
                : EmptyView(
                    icon: Icons.lock_outline,
                    title: room == null
                        ? 'Room not available'
                        : 'Only owners, coaches and captains manage rooms',
                  ),
          );
        }
        final name = _name ??= TextEditingController(text: room.name);
        final busy = vm.save.running || vm.delete.running;
        final c = AppColors.of(context);
        return Scaffold(
          appBar: AppBar(
            title: Text(
              vm.isNew
                  ? 'New channel'
                  : room.isVoice
                  ? 'Voice channel settings'
                  : 'Channel settings',
            ),
          ),
          bottomNavigationBar: DecoratedBox(
            decoration: BoxDecoration(
              color: c.card,
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: SafeArea(
              top: false,
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: busy || !vm.canSave ? null : vm.save.execute,
                      child: Text(vm.isNew ? 'Create' : 'Save'),
                    ),
                  ),
                ),
              ),
            ),
          ),
          body: ConstrainedContent(
            maxWidth: 720,
            child: ListView(
              padding: const EdgeInsets.all(AppSpace.lg),
              children: [
                if (busy) const LinearProgressIndicator(),
                if (vm.isNew) ...[
                  _FieldLabel('Type'),
                  Row(
                    children: [
                      for (final (kind, icon, label, about) in const [
                        (
                          ChatRoomKind.text,
                          Icons.tag,
                          'Text',
                          'Messages, photos, files',
                        ),
                        (
                          ChatRoomKind.voice,
                          Icons.volume_up_rounded,
                          'Voice',
                          'Drop-in audio',
                        ),
                      ]) ...[
                        if (kind != ChatRoomKind.text) const SizedBox(width: 8),
                        Expanded(
                          child: _KindCard(
                            icon: icon,
                            label: label,
                            about: about,
                            selected: room.kind == kind,
                            onTap: busy ? null : () => vm.setKind(kind),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
                TextField(
                  controller: name,
                  enabled: !room.isGeneral,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Channel name',
                    hintText: room.isVoice
                        ? 'e.g. Lounge, Film Room'
                        : 'e.g. Coaches, Handlers, Carpool',
                  ),
                  onChanged: vm.setName,
                ),
                if (vm.folders.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    initialValue: vm.folders.any((f) => f.id == room.folderId)
                        ? room.folderId
                        : null,
                    decoration: const InputDecoration(labelText: 'Folder'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      for (final f in vm.folders)
                        DropdownMenuItem(value: f.id, child: Text(f.name)),
                    ],
                    onChanged: busy ? null : vm.setFolder,
                  ),
                ],
                const SizedBox(height: 18),
                _SectionTitle(
                  title: 'Access by role',
                  subtitle: room.isVoice
                      ? 'Read lets people join and listen; Read & write lets '
                            'them talk too. The owner can always do both.'
                      : 'The owner can always read and post in every room.',
                ),
                _RowsCard(
                  children: [
                    for (final id in vm.audiences)
                      ChatAccessRow(
                        title: vm.audienceLabel(id),
                        value: room.roleAccess(id),
                        onChanged: (a) => vm.setRoleAccess(id, a),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                _SectionTitle(
                  title: 'People',
                  subtitle:
                      'Give someone access beyond their role, like a player '
                      'in the captains room.',
                ),
                if (vm.members.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No other members yet.',
                      style: TextStyle(color: c.muted),
                    ),
                  )
                else
                  _RowsCard(
                    children: [
                      for (final m in vm.members)
                        ChatAccessRow(
                          title: m.name,
                          subtitle: switch (vm.accessByRole(m.uid)) {
                            ChatAccess.none => vm.rolesLabel(m.uid),
                            final a =>
                              '${vm.rolesLabel(m.uid)} · ${a.label} by role',
                          },
                          value: room.userAccess(m.uid),
                          onChanged: (a) => vm.setUserAccess(m.uid, a),
                        ),
                    ],
                  ),
                if (vm.canDelete) ...[
                  const SizedBox(height: 22),
                  // Destructive, but neutral: red is kept for live games,
                  // and the confirm dialog says what's lost.
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      foregroundColor: c.ink,
                      backgroundColor: c.card,
                      side: BorderSide(color: c.border2),
                    ),
                    onPressed: busy ? null : () => _confirmDelete(room),
                    icon: const Icon(Icons.delete_outline, size: 20),
                    label: const Text('Delete room'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A small bold label above a field, e.g. "Type".
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.of(context).ink2,
      ),
    ),
  );
}

/// Text or Voice, as a card to pick when making a room.
class _KindCard extends StatelessWidget {
  const _KindCard({
    required this.icon,
    required this.label,
    required this.about,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String about;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final ink = selected ? c.accentInk : c.ink;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: '$label room. $about',
      excludeSemantics: true,
      child: Material(
        color: selected ? c.accentSoft : c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(
            color: selected ? c.accent : c.border2,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 22, color: ink),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  about,
                  style: TextStyle(
                    fontSize: 12,
                    color: selected ? c.accentInk : c.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [children] in one card, with lines between.
class _RowsCard extends StatelessWidget {
  const _RowsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) Divider(height: 1, color: c.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: child,
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(color: c.muted, fontSize: 13)),
        ],
      ),
    );
  }
}

/// A row with a None / Read / Read & write picker: a segmented control on
/// the field colour, the picked one raised on a card in turf.
class ChatAccessRow extends StatelessWidget {
  const ChatAccessRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final ChatAccess value;
  final ValueChanged<ChatAccess> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final picker = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.field,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: [
          for (final (a, label, flex) in const [
            (ChatAccess.none, 'None', 10),
            (ChatAccess.read, 'Read', 10),
            (ChatAccess.write, 'Read & write', 14),
          ])
            Expanded(
              flex: flex,
              child: Semantics(
                inMutuallyExclusiveGroup: true,
                checked: a == value,
                button: true,
                label: '$title: $label',
                excludeSemantics: true,
                child: Material(
                  color: a == value ? c.card : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: a == value
                        ? BorderSide(color: c.border2)
                        : BorderSide.none,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onChanged(a),
                    child: SizedBox(
                      height: 34,
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: a == value
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: a == value ? c.accent : c.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
        if (subtitle != null)
          Text(subtitle!, style: TextStyle(fontSize: 12, color: c.muted)),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 480
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [label, const SizedBox(height: 8), picker],
              )
            : Row(
                children: [
                  Expanded(child: label),
                  const SizedBox(width: 12),
                  SizedBox(width: 300, child: picker),
                ],
              ),
      ),
    );
  }
}
