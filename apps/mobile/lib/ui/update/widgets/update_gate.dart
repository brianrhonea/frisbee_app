import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/store_links.dart';
import '../view_models/update_gate_viewmodel.dart';
import 'update_required_screen.dart';

/// Wraps the whole app. When [viewModel] says this build is below the lowest
/// allowed it covers everything with the [UpdateRequiredScreen]; the app
/// underneath is kept (so nothing is lost if the gate lifts) but can't be
/// reached or heard by a screen reader. Re-checks the flags when the app comes
/// back to the foreground.
class UpdateGate extends StatefulWidget {
  const UpdateGate({
    super.key,
    required this.viewModel,
    required this.child,
    this.open = _openStore,
  });

  final UpdateGateViewModel viewModel;
  final Widget child;

  /// Opens the store link; a parameter for tests.
  final Future<bool> Function(Uri url) open;

  static Future<bool> _openStore(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.viewModel.recheck();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.viewModel,
    builder: (context, _) {
      final blocked = widget.viewModel.updateRequired;
      // The same tree either way, so the app keeps its state when the gate
      // lifts (or lands).
      return Stack(
        children: [
          Positioned.fill(
            child: ExcludeSemantics(
              excluding: blocked,
              child: IgnorePointer(
                ignoring: blocked,
                child: Offstage(offstage: blocked, child: widget.child),
              ),
            ),
          ),
          if (blocked)
            Positioned.fill(
              child: UpdateRequiredScreen(
                onUpdate: () => widget.open(StoreLinks.forPlatform()),
              ),
            ),
        ],
      );
    },
  );
}
