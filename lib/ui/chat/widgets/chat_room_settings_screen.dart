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
      context.go(Routes.team(vm.teamId, tab: 'chat'));
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
        return Scaffold(
          appBar: AppBar(
            title: Text(vm.isNew ? 'New room' : 'Room settings'),
            actions: [
              if (vm.canDelete)
                IconButton(
                  tooltip: 'Delete room',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: busy ? null : () => _confirmDelete(room),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  onPressed: busy || !vm.canSave ? null : vm.save.execute,
                  child: Text(vm.isNew ? 'Create' : 'Save'),
                ),
              ),
            ],
          ),
          body: ConstrainedContent(
            maxWidth: 720,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (busy) const LinearProgressIndicator(),
                TextField(
                  controller: name,
                  enabled: !room.isGeneral,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Room name',
                    hintText: 'e.g. Coaches, Handlers, Carpool',
                  ),
                  onChanged: vm.setName,
                ),
                const SizedBox(height: 16),
                _SectionTitle(
                  title: 'Access by role',
                  subtitle: 'The owner can always read and post in every room.',
                ),
                for (final role in vm.roles)
                  _AccessRow(
                    title: role.pluralLabel,
                    value: room.roleAccess(role),
                    onChanged: (a) => vm.setRoleAccess(role, a),
                  ),
                const SizedBox(height: 24),
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
                      style: TextStyle(color: AppColors.of(context).muted),
                    ),
                  ),
                for (final m in vm.members)
                  _AccessRow(
                    title: m.name,
                    subtitle: switch (room.roleAccess(m.role)) {
                      ChatAccess.none => m.role.label,
                      final a => '${m.role.label} · ${a.label} by role',
                    },
                    value: room.userAccess(m.uid),
                    onChanged: (a) => vm.setUserAccess(m.uid, a),
                  ),
              ],
            ),
          ),
        );
      },
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
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(subtitle, style: TextStyle(color: c.muted, fontSize: 13)),
        ],
      ),
    );
  }
}

/// A row with a None / Read / Read & write picker.
class _AccessRow extends StatelessWidget {
  const _AccessRow({
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
    final picker = SegmentedButton<ChatAccess>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(value: ChatAccess.none, label: Text('None')),
        ButtonSegment(value: ChatAccess.read, label: Text('Read')),
        ButtonSegment(value: ChatAccess.write, label: Text('Read & write')),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [label, const SizedBox(height: 6), picker],
              )
            : Row(
                children: [
                  Expanded(child: label),
                  const SizedBox(width: 12),
                  picker,
                ],
              ),
      ),
    );
  }
}
