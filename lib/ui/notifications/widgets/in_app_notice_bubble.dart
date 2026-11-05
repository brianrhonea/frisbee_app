import 'package:flutter/material.dart';

import '../../../domain/models/notification.dart';
import '../view_models/in_app_notices_viewmodel.dart';
import 'notifications_screen.dart';

/// A small bubble that drops in at the top while the app is open when a
/// notification arrives. Tap to open it, swipe it up to put it away; it
/// goes by itself after a few seconds.
class InAppNoticeBubble extends StatelessWidget {
  const InAppNoticeBubble({
    super.key,
    required this.viewModel,
    required this.onOpen,
    required this.child,
  });

  final InAppNoticesViewModel viewModel;
  final ValueChanged<String> onOpen;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      child,
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ListenableBuilder(
              listenable: viewModel,
              builder: (context, _) {
                final n = viewModel.current;
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, -0.6),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: n == null
                      ? const SizedBox.shrink()
                      : _Bubble(
                          // Same entry: update in place, no new drop-in.
                          key: ValueKey(n.id),
                          notice: n,
                          onTap: () {
                            if (viewModel.open() case final route?) {
                              onOpen(route);
                            }
                          },
                          onDismiss: viewModel.dismiss,
                        ),
                );
              },
            ),
          ),
        ),
      ),
    ],
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.notice,
    required this.onTap,
    required this.onDismiss,
  });

  final AppNotification notice;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GestureDetector(
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < 0) onDismiss();
          },
          child: Semantics(
            liveRegion: true,
            button: true,
            label: 'Notification',
            child: Material(
              color: scheme.inverseSurface,
              elevation: 6,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 18, 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        categoryIcon(notice.category),
                        size: 20,
                        color: scheme.onInverseSurface,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: notice.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (notice.body.isNotEmpty)
                                TextSpan(text: '  ${notice.body}'),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onInverseSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
