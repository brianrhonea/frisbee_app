import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'disc_throw_hero.dart';

/// Sign-in and sign-up: a disc thrown across a field becomes the Stall 10
/// logo, then the form slides up. On phones the field is on top and the
/// form in a sheet below; on wide screens they sit side by side.
///
/// The throw plays once per launch (moving between sign-in and sign-up
/// doesn't replay it) and not at all when the system asks for less motion.
/// Tap the field to throw again.
class AuthLayout extends StatefulWidget {
  const AuthLayout({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  /// Lets tests see the throw again.
  @visibleForTesting
  static void debugReset() => _AuthLayoutState._played = false;

  @override
  State<AuthLayout> createState() => _AuthLayoutState();
}

class _AuthLayoutState extends State<AuthLayout>
    with SingleTickerProviderStateMixin {
  static bool _played = false;

  late final _throw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );
  bool _started = false;

  /// The form has been shown; replays leave it alone.
  bool _formShown = false;

  late final Animation<double> _form = CurvedAnimation(
    parent: _throw,
    curve: DiscThrowTimeline.form,
  );

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (_played || _reduceMotion) {
      _throw.value = 1;
      _formShown = true;
    } else {
      _played = true;
      _throw.forward().whenCompleteOrCancel(() => _formShown = true);
    }
  }

  void _replay() {
    if (_throw.isAnimating || _reduceMotion) return;
    _formShown = true;
    _throw.forward(from: 0);
  }

  @override
  void dispose() {
    _throw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Light status bar icons over the dark field.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: discHeroBottomColor,
        body: LayoutBuilder(
          builder: (context, box) =>
              box.maxWidth >= 840 ? _wide(context, box) : _narrow(context, box),
        ),
      ),
    );
  }

  Widget _hero() => DiscThrowHero(animation: _throw, onReplay: _replay);

  /// Fades and slides the form up during the first throw. Once it has been
  /// shown it stays put when the disc is thrown again.
  Widget _reveal(Widget child) => AnimatedBuilder(
    animation: _form,
    child: child,
    builder: (context, child) {
      final f = _formShown ? 1.0 : _form.value;
      return Opacity(
        opacity: f,
        child: Transform.translate(
          offset: Offset(0, 32 * (1 - f)),
          child: child,
        ),
      );
    },
  );

  Widget _formBody(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: theme.textTheme.headlineSmall),
        if (widget.subtitle case final s?) ...[
          const SizedBox(height: 4),
          Text(
            s,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 20),
        widget.child,
      ],
    );
  }

  Widget _narrow(BuildContext context, BoxConstraints box) {
    final heroHeight = (box.maxHeight * 0.42).clamp(270.0, 380.0);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: heroHeight, child: _hero()),
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, box.maxHeight - heroHeight),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: _reveal(_formBody(context)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wide(BuildContext context, BoxConstraints box) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _hero()),
        SizedBox(
          width: math.min(520, box.maxWidth * 0.45),
          child: ColoredBox(
            color: theme.scaffoldBackgroundColor,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(40),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: _reveal(_formBody(context)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
