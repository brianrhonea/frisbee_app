import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../domain/models/direct_message.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/app_search_field.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/user_avatar.dart';
import '../view_models/group_members_viewmodel.dart';

/// New message: pick one person for a direct message, or several for a
/// group (which can then be named). Or add people to a group.
class GroupMembersScreen extends StatefulWidget {
  const GroupMembersScreen({super.key, required this.viewModel});

  final GroupMembersViewModel viewModel;

  @override
  State<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<GroupMembersScreen> {
  GroupMembersViewModel get vm => widget.viewModel;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    vm.save.addListener(_onSave);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    vm.save.removeListener(_onSave);
    super.dispose();
  }

  void _onSave() {
    switch (vm.save.result) {
      case Ok(:final value):
        vm.save.clearResult();
        if (notAddedMessage(value.notAdded) case final note?) {
          showSnackBar(context, note);
        }
        if (vm.isNew) {
          context.pushReplacement(Routes.conversation(value.id));
        } else {
          context.pop();
        }
      case final Error<GroupAdded> e:
        showErrorSnackBar(context, e);
        vm.save.clearResult();
      case null:
        break;
    }
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => vm.search.execute(text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([vm, vm.search, vm.save]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(vm.isNew ? 'New message' : 'Add people'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: vm.canSave ? vm.save.execute : null,
                child: vm.save.running
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        !vm.isNew
                            ? 'Add'
                            : vm.makesGroup
                            ? 'Create group'
                            : 'Chat',
                      ),
              ),
            ),
          ],
        ),
        body: ConstrainedContent(
          maxWidth: 720,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (vm.makesGroup)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    maxLength: Conversation.maxGroupName,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Group name (optional)',
                      hintText: 'e.g. Hat league carpool',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: vm.setName,
                  ),
                ),
              if (vm.picked.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final p in vm.picked)
                        InputChip(
                          avatar: UserAvatar(
                            uid: p.uid,
                            name: p.name,
                            photoUrl: p.photoUrl,
                            radius: 12,
                          ),
                          label: Text(p.name),
                          onDeleted: () => vm.toggle(p),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: AppSearchField(
                  autofocus: true,
                  hint: 'Search people by name',
                  onChanged: _onChanged,
                  onSubmitted: vm.search.execute,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  vm.isNew && vm.picked.isEmpty
                      ? 'Pick one person to message them, or several to '
                            'start a group.'
                      : vm.isNew && !vm.makesGroup
                      ? 'Pick more people to make it a group. Groups can '
                            'include people who follow you.'
                      : 'You can add people who follow you. '
                            '${vm.room > 0 ? '${vm.room} more can join.' : 'The group is full.'}',
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ),
              Expanded(child: _results(c)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results(AppColors c) {
    if (vm.search.running) return const LoadingView();
    if (vm.search.error) return ErrorView(error: vm.search.result);
    if (vm.noMatches) {
      return const EmptyView(
        icon: Icons.person_search_outlined,
        title: 'No one found',
        message: 'Try their first or last name.',
      );
    }
    final results = vm.results;
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Type at least ${GroupMembersViewModel.minQueryLength} letters of '
          'a name.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.muted),
        ),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, i) {
        final p = results[i];
        final picked = vm.isPicked(p);
        return CheckboxListTile(
          value: picked,
          enabled: picked || vm.room > 0,
          secondary: UserAvatar(uid: p.uid, name: p.name, photoUrl: p.photoUrl),
          title: Text(p.name),
          subtitle: p.username == null ? null : Text('@${p.username}'),
          onChanged: (_) => vm.toggle(p),
        );
      },
    );
  }
}
