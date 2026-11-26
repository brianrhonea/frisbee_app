import 'package:flutter/material.dart';

import '../themes/theme.dart';
import 'tone.dart';

/// What a [StatusPill] means. Six tones, all from the semantic colour
/// tokens (a soft fill with dark text; see design-tokens.md):
///
/// * [neutral]: a kind or a quiet status (draft, ended, maybe).
/// * [accent]: the app's own colour (open to you, captain, pinned).
/// * [success]: done, going, open, on. Green is only for success.
/// * [warning]: needs you (needs RSVP, score due, finish setup).
/// * [live]: happening now. Red is only for live.
/// * [error]: failed, cancelled, rejected.
enum PillTone {
  neutral,
  accent,
  success,
  warning,
  live,
  error;

  /// Fill, text and (for the solid variant) fill/text colours.
  ({Color soft, Color ink, Color solid, Color onSolid}) of(
    AppColors c,
  ) => switch (this) {
    neutral => (soft: c.field, ink: c.ink2, solid: c.ink, onSolid: c.card),
    accent => (
      soft: c.accentSoft,
      ink: c.accentInk,
      solid: c.highlight,
      onSolid: c.onHighlight,
    ),
    success => (
      soft: c.positiveSoft,
      ink: c.positive,
      solid: c.positive,
      onSolid: c.card,
    ),
    warning => (
      soft: c.highlightSoft,
      ink: c.highlightInk,
      solid: c.highlightInk,
      onSolid: c.highlightSoft,
    ),
    live => (soft: c.liveSoft, ink: c.liveInk, solid: c.live, onSolid: c.card),
    error => (soft: c.errorSoft, ink: c.error, solid: c.error, onSolid: c.card),
  };
}

/// The older [Tone] (kind and status colours) as a [PillTone].
extension ToneAsPill on Tone {
  PillTone get pill => switch (this) {
    Tone.grey => PillTone.neutral,
    Tone.amber => PillTone.warning,
    Tone.red => PillTone.live,
    Tone.green => PillTone.success,
  };
}

/// The one pill for every status: going, open, live, captain, needs you,
/// a count. A soft fill with dark text and always a text [label], so the
/// meaning never rests on colour alone; an optional [icon] or [dot] sits
/// before it.
///
/// [solid] flips it to a solid fill for the single most urgent thing on a
/// screen, or for counts. The text is one line and shortens with an
/// ellipsis when the parent is narrow; it grows with the text scale.
///
/// Website counterpart: `StatusPill` (apps/web).
class StatusPill extends StatelessWidget {
  const StatusPill(
    this.label, {
    super.key,
    this.tone = PillTone.neutral,
    this.icon,
    this.dot = false,
    this.solid = false,
    this.maxWidth,
  });

  /// An unread or item count: solid, "99+" above 99. The semantics label
  /// is the number itself.
  factory StatusPill.count(
    int count, {
    Key? key,
    PillTone tone = PillTone.accent,
    bool solid = true,
  }) => StatusPill(
    count > 99 ? '99+' : '$count',
    key: key,
    tone: tone,
    solid: solid,
  );

  final String label;
  final PillTone tone;

  /// Shown before the label (12 px), in the pill's text colour.
  final IconData? icon;

  /// A filled dot before the label (for live).
  final bool dot;
  final bool solid;

  /// Narrowest cap; the label ends in an ellipsis beyond it.
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final p = tone.of(AppColors.of(context));
    final fill = solid ? p.solid : p.soft;
    final ink = solid ? p.onSolid : p.ink;
    final lead = icon != null || dot;
    return Container(
      constraints: BoxConstraints(
        minWidth: 20,
        maxWidth: maxWidth ?? double.infinity,
      ),
      padding: EdgeInsets.fromLTRB(lead ? AppSpace.sm : 10, 3, 10, 3),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: ink),
            const SizedBox(width: AppSpace.xs),
          ],
          if (dot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
