import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/chat.dart';
import '../../core/themes/theme.dart';

/// Double-tap on a message, as iMessage: a bubble of quick reactions
/// floats just above it, with a + for any other emoji. Returns the emoji
/// picked, or null when dismissed. [mine] is the user's current one,
/// highlighted (picking it again takes it back).
Future<String?> showReactionBubble(
  BuildContext context, {
  required Rect anchor,
  String? mine,
  bool alignEnd = false,
}) async {
  HapticFeedback.selectionClick();
  final picked = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close reactions',
    barrierColor: Colors.black.withValues(alpha: 0.12),
    transitionDuration: AppMotion.of(context, AppMotion.fast),
    pageBuilder: (context, _, _) =>
        _BubbleLayer(anchor: anchor, mine: mine, alignEnd: alignEnd),
    transitionBuilder: (context, animation, _, child) =>
        MediaQuery.disableAnimationsOf(context)
        ? child
        : FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween(begin: 0.85, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: AppMotion.easing),
              ),
              child: child,
            ),
          ),
  );
  if (picked != _more || !context.mounted) return picked;
  return showEmojiPicker(context, mine: mine);
}

/// What the bubble's + returns, so the picker opens once it has closed.
const _more = '+';

/// Every emoji in [reactionGroups], by group, in a sheet. Returns the one
/// picked, or null.
Future<String?> showEmojiPicker(BuildContext context, {String? mine}) =>
    showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: AppMotion.sheetStyle(context),
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      builder: (context) => _EmojiPicker(mine: mine),
    );

class _BubbleLayer extends StatelessWidget {
  const _BubbleLayer({required this.anchor, required this.alignEnd, this.mine});

  final Rect anchor;
  final String? mine;

  /// Over the user's own messages, on the right.
  final bool alignEnd;

  static const _height = 52.0;
  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    // Above the message, or under it when it's near the top of the screen,
    // so it never sits over the page's title bar.
    final above = anchor.top - _height - _gap >= pad.top + kToolbarHeight + 8;
    final top = above
        ? anchor.top - _height - _gap
        : (anchor.bottom + _gap).clamp(pad.top + 8, size.height - _height - 8);
    return Stack(
      children: [
        Positioned(
          top: top,
          left: 8,
          right: 8,
          height: _height,
          child: Align(
            // Lines up with the side the message is on.
            alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
            child: ReactionBubble(
              mine: mine,
              onPick: (e) => Navigator.pop(context, e),
              onMore: () => Navigator.pop(context, _more),
            ),
          ),
        ),
      ],
    );
  }
}

/// The quick reactions in a pill, then a + for more.
class ReactionBubble extends StatelessWidget {
  const ReactionBubble({
    super.key,
    required this.onPick,
    required this.onMore,
    this.mine,
  });

  final ValueChanged<String> onPick;
  final VoidCallback onMore;
  final String? mine;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Material(
      color: c.card,
      elevation: 6,
      shadowColor: Colors.black38,
      shape: StadiumBorder(side: BorderSide(color: c.border)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in quickReactions)
                _EmojiButton(
                  emoji: e,
                  selected: e == mine,
                  size: 44,
                  onTap: () => onPick(e),
                ),
              // Their own pick from the +, so it can be taken back here.
              if (mine != null && !quickReactions.contains(mine))
                _EmojiButton(
                  emoji: mine!,
                  selected: true,
                  size: 44,
                  onTap: () => onPick(mine!),
                ),
              Semantics(
                button: true,
                label: 'More emoji',
                child: InkResponse(
                  radius: 22,
                  onTap: onMore,
                  child: Container(
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.field,
                    ),
                    child: Icon(Icons.add, size: 22, color: c.ink2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmojiButton extends StatelessWidget {
  const _EmojiButton({
    required this.emoji,
    required this.selected,
    required this.size,
    required this.onTap,
  });

  final String emoji;
  final bool selected;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: 'React $emoji',
      excludeSemantics: true,
      child: InkResponse(
        radius: size / 2,
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? c.accentSoft : null,
            border: selected ? Border.all(color: c.accent, width: 1.5) : null,
          ),
          child: Text(emoji, style: TextStyle(fontSize: size * 0.56)),
        ),
      ),
    );
  }
}

class _EmojiPicker extends StatelessWidget {
  const _EmojiPicker({this.mine});

  final String? mine;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SafeArea(
      child: CustomScrollView(
        shrinkWrap: true,
        slivers: [
          for (final (name, emoji) in reactionGroups) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              sliver: SliverToBoxAdapter(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.muted,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              sliver: SliverGrid.extent(
                maxCrossAxisExtent: 48,
                children: [
                  for (final e in emoji)
                    _EmojiButton(
                      emoji: e,
                      selected: e == mine,
                      size: 44,
                      onTap: () => Navigator.pop(context, e),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
