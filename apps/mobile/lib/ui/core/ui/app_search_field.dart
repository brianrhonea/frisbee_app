import 'package:flutter/material.dart';

import '../themes/theme.dart';

/// The one search box: same height, icon and clear button on every page.
/// [hint] says what it searches, e.g. "Search messages" for a page's own
/// list; the app-wide search (Explore) says "Search Stall 10".
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.hint,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.hintTrailing,
  });

  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  /// Shown at the end while the box is empty, e.g. a shortcut's key cap.
  final Widget? hintTrailing;

  static const height = 44.0;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  TextEditingController? _own;
  TextEditingController get _text =>
      widget.controller ?? (_own ??= TextEditingController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  void _clear() {
    _text.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SizedBox(
      height: AppSearchField.height,
      child: ValueListenableBuilder(
        valueListenable: _text,
        builder: (context, value, _) => TextField(
          controller: _text,
          autofocus: widget.autofocus,
          textInputAction: TextInputAction.search,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(fontSize: 14, color: c.muted),
            prefixIcon: Icon(Icons.search, size: 20, color: c.muted),
            suffixIcon: value.text.isEmpty
                ? switch (widget.hintTrailing) {
                    final hint? => Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: hint,
                    ),
                    null => null,
                  }
                : IconButton(
                    tooltip: 'Clear',
                    icon: Icon(Icons.close, size: 18, color: c.muted),
                    onPressed: _clear,
                  ),
            suffixIconConstraints: value.text.isEmpty
                ? const BoxConstraints(minHeight: 24)
                : null,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}
