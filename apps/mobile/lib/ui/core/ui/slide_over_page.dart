import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Width of a [slideOverPage] panel on wide windows.
const slideOverPanelWidth = 440.0;

/// A page that slides in from the right over the current one, the way a
/// phone opens a conversation or settings. On iOS and macOS phones-sized
/// windows it's the native page, so swiping from the left edge goes back,
/// following the finger.
///
/// With [panelOnWide], wide windows (as [context] is when it opens) show
/// it as a panel down the right edge over the dimmed page instead of full
/// screen, like a drawer; clicking outside closes it. [dim] darkens what's
/// behind; turn it off for a panel opened from another panel.
Page<void> slideOverPage(
  BuildContext context,
  LocalKey key,
  Widget child, {
  bool panelOnWide = false,
  bool dim = true,
}) {
  final panel =
      panelOnWide &&
      MediaQuery.sizeOf(context).width >= slideOverPanelWidth * 1.6;
  if (!panel &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS)) {
    return CupertinoPage(key: key, child: child);
  }
  return CustomTransitionPage(
    key: key,
    child: panel
        ? Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: slideOverPanelWidth,
              child: Material(
                elevation: 12,
                clipBehavior: Clip.antiAlias,
                child: child,
              ),
            ),
          )
        : child,
    opaque: !panel,
    barrierDismissible: panel,
    barrierColor: panel && dim ? Colors.black38 : null,
    barrierLabel: panel ? 'Close' : null,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final slide = Tween(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(curved);
      if (panel) {
        // Only the panel moves, from just off the right edge.
        return AnimatedBuilder(
          animation: curved,
          builder: (context, child) => Transform.translate(
            offset: Offset(slideOverPanelWidth * (1 - curved.value), 0),
            child: child,
          ),
          child: child,
        );
      }
      return SlideTransition(
        position: slide,
        // A shadow along the leading edge, so the page reads as on top
        // while it moves (dark pages otherwise blend together).
        child: DecoratedBox(
          decoration: const BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 16,
                offset: Offset(-2, 0),
              ),
            ],
          ),
          child: child,
        ),
      );
    },
  );
}
