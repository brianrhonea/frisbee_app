import 'package:flutter/material.dart';

import '../themes/theme.dart';
import 'app_segmented_button.dart';

/// Tabs drawn as one pill of segments; the selected tab is filled indigo
/// ([AppColors.chipOn]) with bolder [AppColors.onChipOn] text.
///
/// Every segment is at least 48 px tall and its label stays on one line, so
/// when the labels don't fit (many tabs, or large text) the row scrolls
/// sideways and keeps the selected tab in view instead of squeezing. When
/// they fit, the segments share the width equally. Arrow keys move focus
/// between tabs; Enter or Space selects.
///
/// For a tab bar driven by a [TabController] use `SegmentedTabBar`; for a
/// choice that is not navigation use [AppSegmentedButton]. Website
/// counterpart: `SegmentedTabs` (apps/web).
class SegmentedTabs extends StatefulWidget {
  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
    this.icons,
    this.padding = EdgeInsets.zero,
  });

  final List<String> labels;

  /// Index of the selected tab; -1 for none.
  final int selected;
  final ValueChanged<int> onSelect;

  /// Optional leading icon per tab (same length as [labels]).
  final List<Widget?>? icons;

  /// Around the control.
  final EdgeInsets padding;

  @override
  State<SegmentedTabs> createState() => _SegmentedTabsState();
}

class _SegmentedTabsState extends State<SegmentedTabs> {
  late List<GlobalKey> _keys = _makeKeys();

  List<GlobalKey> _makeKeys() => [for (final _ in widget.labels) GlobalKey()];

  @override
  void didUpdateWidget(SegmentedTabs old) {
    super.didUpdateWidget(old);
    if (old.labels.length != widget.labels.length) _keys = _makeKeys();
    if (old.selected != widget.selected) _reveal();
  }

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  /// Scrolls the selected tab into view, after this frame's layout.
  void _reveal() {
    final i = widget.selected;
    if (i < 0 || i >= _keys.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = i < _keys.length ? _keys[i].currentContext : null;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        duration: AppMotion.of(ctx, AppMotion.base),
        curve: AppMotion.easing,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: widget.padding,
      child: LayoutBuilder(
        builder: (context, box) {
          final bar = DecoratedBox(
            decoration: ShapeDecoration(
              color: c.card,
              shape: StadiumBorder(side: BorderSide(color: c.border2)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    // Fill the width when everything fits.
                    minWidth: box.hasBoundedWidth ? box.maxWidth - 2 : 0,
                  ),
                  child: IntrinsicWidth(
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < widget.labels.length; i++)
                            Expanded(
                              child: KeyedSubtree(
                                key: _keys[i],
                                child: AppSegment(
                                  selected: i == widget.selected,
                                  onTap: () => widget.onSelect(i),
                                  child: _label(i),
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
          );
          return FocusTraversalGroup(child: bar);
        },
      ),
    );
  }

  Widget _label(int i) {
    final text = Text(
      widget.labels[i],
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
    final icon = widget.icons?[i];
    if (icon == null) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [icon, const SizedBox(width: 6), text],
    );
  }
}
