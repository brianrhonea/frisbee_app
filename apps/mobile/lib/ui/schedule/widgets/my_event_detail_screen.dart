import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../calendar/widgets/add_to_calendar.dart';
import '../../../domain/models/team_event.dart';
import 'schedule_widgets.dart';
import '../../../routing/routes.dart';
import '../../core/ui/back_or.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/status_views.dart';
import '../view_models/my_event_detail_viewmodel.dart';
import 'event_detail_screen.dart' show EventHeader, EventNotes;

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
    if (e.series != null) {
      // A repeating event: this one, or it and every later one.
      final scope = await askSeriesScope(
        context,
        title: 'Delete "${e.title}"?',
        action: 'Delete',
      );
      if (scope != null) vm.deleteEvent.execute(scope);
      return;
    }
    if (await confirmDialog(
      context,
      title: 'Delete "${e.title}"?',
      message: 'It will be removed from your schedule.',
      confirmLabel: 'Delete',
      destructive: true,
    )) {
      vm.deleteEvent.execute(SeriesScope.one);
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
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
              children: [
                EventHeader(
                  event: e,
                  owner: 'My calendar',
                  personal: true,
                  calendarButton: AddToCalendarButton(
                    event: e,
                    uid: 'me-${e.id}@stall10.app',
                  ),
                ),
                if (e.notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  EventNotes(notes: e.notes),
                ],
                const SizedBox(height: 12),
                const _PrivateNote(),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Who can see a personal event.
class _PrivateNote extends StatelessWidget {
  const _PrivateNote();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.field,
        borderRadius: BorderRadius.circular(controlRadius),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 18, color: c.ink2),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Personal event · only you can see it',
              style: TextStyle(fontSize: 13, color: c.ink2),
            ),
          ),
        ],
      ),
    );
  }
}
