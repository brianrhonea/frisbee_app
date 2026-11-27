import 'package:flutter/material.dart';

import 'app_button.dart';
import 'error_message.dart';
import 'skeleton.dart';
import '../themes/theme.dart';

/// A page or list on the way: placeholder rows, not a spinner (C9). Read
/// as "Loading" (see [Skeleton]).
///
/// Website counterpart: `LoadingState` (apps/web).
class LoadingState extends StatelessWidget {
  const LoadingState({super.key});

  @override
  Widget build(BuildContext context) =>
      const Align(alignment: Alignment.topCenter, child: SkeletonList());
}

/// Something failed (C9): the reason in words, with a Retry button when
/// [onRetry] is given. Announced to screen readers as it appears.
///
/// Website counterpart: `ErrorState` (apps/web).
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(errorMessage(error), textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              AppButton.secondary(
                'Retry',
                icon: Icons.refresh,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Nothing here yet (C9): an icon (or [art]), a [title], a [message] that
/// says what to do next, and an optional [action] button.
///
/// Website counterpart: `EmptyState` (apps/web).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon,
    this.art,
    required this.title,
    this.message,
    this.action,
  }) : assert(icon != null || art != null);

  final IconData? icon;

  /// Drawn in place of [icon], e.g. a `DiscIcon`; sized and coloured
  /// like the icon.
  final Widget? art;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme(
              data: IconThemeData(size: 56, color: theme.colorScheme.outline),
              child: art ?? Icon(icon),
            ),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 4),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Centers content and caps its width on large screens.
class ConstrainedContent extends StatelessWidget {
  const ConstrainedContent({
    super.key,
    required this.child,
    this.maxWidth = 900,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
