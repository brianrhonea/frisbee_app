import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/outbox.dart';
import '../../core/themes/theme.dart';
import '../view_models/outbox_viewmodel.dart';

/// A strip across the top of the app while offline, or while anything
/// waits to send or was turned down; tapping it lists them. Also says so
/// each time something is queued instead of sent.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({
    super.key,
    required this.viewModel,
    required this.child,
    this.messengerKey,
    this.navigatorContext,
  });

  final OutboxViewModel viewModel;
  final Widget child;
  final GlobalKey<ScaffoldMessengerState>? messengerKey;

  /// A context under the app's navigator, for the list's sheet.
  final BuildContext? Function()? navigatorContext;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  StreamSubscription<OutboxJob>? _queued;

  @override
  void initState() {
    super.initState();
    _queued = widget.viewModel.queued.listen((job) {
      widget.messengerKey?.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(queuedNotice(job))));
    });
  }

  @override
  void dispose() {
    unawaited(_queued?.cancel());
    super.dispose();
  }

  void _openList() {
    final context = widget.navigatorContext?.call() ?? this.context;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => OutboxSheet(viewModel: widget.viewModel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.viewModel,
    builder: (context, _) {
      final vm = widget.viewModel;
      if (!vm.showBanner) return widget.child;
      final c = AppColors.of(context);
      final failed = vm.online && vm.waitingCount == 0;
      // Turned down: the user's to sort out, so amber. Offline or
      // waiting: a quiet field-coloured strip.
      final background = failed ? c.highlightSoft : c.field;
      final foreground = failed ? c.highlightInk : c.ink2;
      return Column(
        children: [
          Material(
            color: background,
            child: SafeArea(
              bottom: false,
              child: InkWell(
                onTap: vm.jobs.isEmpty ? null : _openList,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        vm.online ? Icons.sync : Icons.cloud_off_outlined,
                        size: 18,
                        color: foreground,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          vm.bannerText,
                          style: TextStyle(color: foreground),
                        ),
                      ),
                      if (vm.jobs.isNotEmpty)
                        Icon(Icons.chevron_right, color: foreground),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            // The banner took the top inset.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: widget.child,
            ),
          ),
        ],
      );
    },
  );
}

/// What's waiting to send, with Retry and Discard.
class OutboxSheet extends StatelessWidget {
  const OutboxSheet({super.key, required this.viewModel});

  final OutboxViewModel viewModel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final jobs = viewModel.jobs;
      final theme = Theme.of(context);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Waiting to send',
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (jobs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Everything has been sent.'),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final job in jobs)
                    ListTile(
                      key: ValueKey(job.id),
                      title: Text(
                        job.preview.isEmpty
                            ? job.label
                            : '${job.label}: ${job.preview}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          OutboxViewModel.stateOf(job),
                          if (job.files.isNotEmpty)
                            job.files.length == 1
                                ? '1 attachment'
                                : '${job.files.length} attachments',
                        ].join(' · '),
                        style: job.state == OutboxState.failed
                            ? TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.of(context).highlightInk,
                              )
                            : null,
                      ),
                      trailing: job.state == OutboxState.sending
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (job.state == OutboxState.failed)
                                  IconButton(
                                    tooltip: 'Try again',
                                    icon: const Icon(Icons.refresh),
                                    onPressed: () =>
                                        viewModel.retry.execute(job.id),
                                  ),
                                IconButton(
                                  tooltip: 'Discard',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () =>
                                      viewModel.discard.execute(job.id),
                                ),
                              ],
                            ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
