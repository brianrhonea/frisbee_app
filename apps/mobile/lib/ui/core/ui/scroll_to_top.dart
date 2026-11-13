import 'package:flutter/material.dart';

/// Scrolls [controller]'s list to the top when the status bar is tapped
/// (iOS), or the tab the page is on is tapped again ([ScrollToTop.request]),
/// as a phone's own apps do.
///
/// Only the page on screen answers: the current route, in the tab that's
/// showing. A [reverse] list (a chat, newest at the bottom) goes to its
/// oldest loaded message instead; one that loads more as it reaches the
/// top (see MessageThreadView) then fetches the page above, so each tap
/// goes further back until the first message.
class ScrollToTop extends StatefulWidget {
  const ScrollToTop({
    super.key,
    required this.controller,
    required this.child,
    this.reverse = false,
  });

  final ScrollController controller;
  final bool reverse;
  final Widget child;

  static final _requests = ValueNotifier<int>(0);

  /// Asks the page on screen to scroll to its top (the current tab was
  /// tapped again).
  static void request() => _requests.value++;

  /// The status bar was tapped; for tests (iOS sends it to the binding).
  @visibleForTesting
  static void statusBarTapped() {
    for (final s in _ScrollToTopState._live.toList()) {
      s.handleStatusBarTap();
    }
  }

  @override
  State<ScrollToTop> createState() => _ScrollToTopState();
}

class _ScrollToTopState extends State<ScrollToTop> with WidgetsBindingObserver {
  static final _live = <_ScrollToTopState>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ScrollToTop._requests.addListener(_scroll);
    _live.add(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ScrollToTop._requests.removeListener(_scroll);
    _live.remove(this);
    super.dispose();
  }

  @override
  void handleStatusBarTap() => _scroll();

  /// Whether this is the page on screen: its route is on top, and the tab
  /// it's in isn't hidden behind another (hidden tabs have tickers off).
  bool get _onScreen {
    if (!mounted) return false;
    if (!TickerMode.valuesOf(context).enabled) return false;
    final route = ModalRoute.of(context);
    return route == null || route.isCurrent;
  }

  void _scroll() {
    final c = widget.controller;
    if (!_onScreen || !c.hasClients) return;
    for (final p in c.positions) {
      final target = widget.reverse ? p.maxScrollExtent : p.minScrollExtent;
      if ((p.pixels - target).abs() < 1) continue;
      p.animateTo(
        target,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
