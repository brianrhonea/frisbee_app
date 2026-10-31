import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/team_event.dart';
import '../../../routing/routes.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../view_models/my_event_detail_viewmodel.dart';
import 'event_detail_screen.dart' show EventHeader;

/// A personal event: details plus edit and delete. Only its owner sees it.
class MyEventDetailScreen extends StatefulWidget {
  const MyEventDetailScreen({super.key, required this.viewModel});

  final MyEventDetailViewModel viewModel;

  @override
  State<MyEventDetailScreen> createState() => _MyEventDetailScreenState();
}

class _MyEventDetailScreenState extends State<MyEventDetailScreen> {
  MyEventDetailViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.deleteEvent.addListener(_onDelete);
  }

  @override
  void dispose() {
    vm.deleteEvent.removeListener(_onDelete);
    super.dispose();
  }

  void _onDelete() {
    final cmd = vm.deleteEvent;
    if (cmd.completed) {
      cmd.clearResult();
      context.canPop() ? context.pop() : context.go(Routes.schedule);
    } else if (cmd.error) {
      showErrorSnackBar(context, cmd.result);
      cmd.clearResult();
    }
  }

  Future<void> _delete(TeamEvent e) async {
    if (await confirmDialog(
      context,
      title: 'Delete "${e.title}"?',
      message: 'It will be removed from your schedule.',
      confirmLabel: 'Delete',
      destructive: true,
    )) {
      vm.deleteEvent.execute();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) {
      final e = vm.event;
      if (!vm.loaded) {
        return Scaffold(
          appBar: AppBar(leading: backOr(context, Routes.schedule)),
          body: const LoadingView(),
        );
      }
      if (e == null) {
        return Scaffold(
          appBar: AppBar(leading: backOr(context, Routes.schedule)),
          body: vm.error != null
              ? ErrorView(error: vm.error)
              : const EmptyView(
                  icon: Icons.event_busy_outlined,
                  title: 'Event not available',
                  message: 'It may have been deleted.',
                ),
        );
      }
      return Scaffold(
        appBar: AppBar(
          leading: backOr(context, Routes.schedule),
          title: Text(e.type.label),
          actions: [
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push(Routes.editMyEvent(vm.eventId)),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(e),
            ),
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                EventHeader(event: e),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Personal event · only you can see it',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
