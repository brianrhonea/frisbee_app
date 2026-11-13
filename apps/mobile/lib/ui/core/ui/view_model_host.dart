import 'package:flutter/widgets.dart';

/// Creates a ViewModel once for the lifetime of a route and disposes it
/// when the route is removed, so router rebuilds don't reset view state.
class ViewModelHost<T extends ChangeNotifier> extends StatefulWidget {
  const ViewModelHost({super.key, required this.create, required this.builder});

  final T Function(BuildContext context) create;
  final Widget Function(BuildContext context, T viewModel) builder;

  @override
  State<ViewModelHost<T>> createState() => _ViewModelHostState<T>();
}

class _ViewModelHostState<T extends ChangeNotifier>
    extends State<ViewModelHost<T>> {
  late final T _viewModel = widget.create(context);

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _viewModel);
}
