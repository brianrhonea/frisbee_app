import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../themes/theme.dart';
import 'date_badge.dart';
import 'status_pill.dart';

/// Where the user stands on an event, shown as the RSVP chip of an
/// [EventCard]. The label is always text, never colour alone.
enum EventRsvp {
  going('Going', PillTone.success, Icons.check),
  maybe('Maybe', PillTone.neutral, null),
  declined("Can't go", PillTone.neutral, null),
  needsReply('Needs RSVP', PillTone.warning, Icons.priority_high);

  const EventRsvp(this.label, this.tone, this.icon);

  final String label;
  final PillTone tone;
  final IconData? icon;
}

/// An event in a list (C8): a [DateBadge], the [title], a line of [meta]
/// (time, place), and chips for the RSVP, "Cancelled" and "Repeats".
///
/// A [cancelled] event is struck through and grey, and says "Cancelled"
/// in words. Chips wrap under the text when the row is narrow or the text
/// is large; the whole card is one tap target at least 72 px tall and is
/// read as a single item.
///
/// Website counterpart: `EventCard` (apps/web).
class EventCard extends StatelessWidget {
  const EventCard({
    super.key,
    required this.date,
    required this.title,
    this.meta,
    this.rsvp,
    this.cancelled = false,
    this.recurring = false,
    this.onTap,
  });

  final DateTime date;
  final String title;

  /// e.g. "6:30 PM · Pier 62 field".
  final String? meta;
  final EventRsvp? rsvp;
  final bool cancelled;
  final bool recurring;
  final VoidCallback? onTap;

  static const minHeight = 72.0;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final chips = [
      if (cancelled)
        const StatusPill('Cancelled', tone: PillTone.error, icon: Icons.block),
      if (!cancelled && rsvp != null)
        StatusPill(rsvp!.label, tone: rsvp!.tone, icon: rsvp!.icon),
      if (recurring) const StatusPill('Repeats', icon: Icons.repeat),
    ];
    final spoken = [
      DateFormat.MMMMd().format(date),
      title,
      ?meta,
      if (cancelled) 'Cancelled',
      if (!cancelled && rsvp != null) rsvp!.label,
      if (recurring) 'Repeats',
    ].join(', ');
    final body = Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DateBadge(date: date, size: 44, cancelled: cancelled),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cancelled ? c.muted : c.ink,
                    decoration: cancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (meta != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      meta!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.ink2),
                    ),
                  ),
                if (chips.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.sm),
                    child: Wrap(
                      spacing: AppSpace.xs + 2,
                      runSpacing: AppSpace.xs + 2,
                      children: chips,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      button: onTap != null,
      label: spoken,
      excludeSemantics: true,
      onTap: onTap,
      child: Card(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minHeight),
          child: onTap == null ? body : InkWell(onTap: onTap, child: body),
        ),
      ),
    );
  }
}
