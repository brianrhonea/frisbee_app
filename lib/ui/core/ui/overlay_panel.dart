import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../themes/theme.dart';
import 'layout.dart' show ScreenSize;

/// Opens a form over the current page instead of on a page of its own: a
/// bottom sheet on phones, and on wide screens a card only as tall as its
/// content. [builder] gets whether it's in that card ([PanelFrame.fitContent]).
/// Completes with what the panel was closed with.
Future<T?> showOverlayPanel<T>(
  BuildContext context, {
  required Widget Function(BuildContext context, bool fitContent) builder,
}) {
  if (ScreenSize.of(context).isMobile) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Dragging would close it without asking; the close button and the
      // barrier ask first when there are changes.
      enableDrag: false,
      clipBehavior: Clip.antiAlias,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.92,
        child: builder(context, false),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (context) => OverlayCard(child: builder(context, true)),
  );
}

/// The panel on wide screens: a card only as tall as its content (up to
/// most of the window, then it scrolls). It sits on a clear page of its own
/// so error messages show above the dimmed background. Clicking outside
/// the card closes it, through the panel's PopScope, so a form with changes
/// can ask first.
class OverlayCard extends StatelessWidget {
  const OverlayCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final maxHeight = math.min(MediaQuery.sizeOf(context).height * 0.85, 820.0);
    return ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                // Taps on the card stay on the card.
                child: GestureDetector(
                  onTap: () {},
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 640,
                      maxHeight: maxHeight,
                    ),
                    child: Material(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      elevation: 6,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.circular(cardRadius + 6),
                      ),
                      child: child,
                    ),
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

/// A panel's header and body. In the bottom sheet, a page with an app bar.
/// In the wide-screen card ([fitContent]), the header over [body], together
/// only as tall as they need; [body] should then shrink-wrap its list.
class PanelFrame extends StatelessWidget {
  const PanelFrame({
    super.key,
    required this.fitContent,
    required this.close,
    this.title,
    this.actions = const [],
    required this.body,
  });

  final bool fitContent;
  final Widget close;
  final String? title;
  final List<Widget> actions;
  final Widget Function(bool fit) body;

  /// Loading and error views, given some height in the card.
  static Widget status(bool fitContent, Widget child) =>
      fitContent ? SizedBox(height: 260, child: child) : child;

  @override
  Widget build(BuildContext context) {
    final bar = AppBar(
      leading: close,
      title: title == null ? null : Text(title!),
      actions: actions,
      primary: !fitContent,
      automaticallyImplyLeading: false,
    );
    if (!fitContent) return Scaffold(appBar: bar, body: body(false));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: kToolbarHeight, child: bar),
        Divider(height: 1, color: AppColors.of(context).border),
        Flexible(child: body(true)),
      ],
    );
  }
}
