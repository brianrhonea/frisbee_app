import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// AppBar `leading` for full-screen pages: null (the normal back button)
/// when there is a page to return to, otherwise a back button that goes to
/// [fallback], e.g. when the page was opened from a link.
Widget? backOr(BuildContext context, String fallback) {
  final router = GoRouter.maybeOf(context);
  if (router == null || router.canPop()) return null;
  return IconButton(
    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
    icon: const BackButtonIcon(),
    onPressed: () => router.go(fallback),
  );
}
