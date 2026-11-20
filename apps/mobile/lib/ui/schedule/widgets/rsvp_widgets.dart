import 'package:flutter/material.dart';

import '../../../domain/models/team_event.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/scoreboard.dart';

/// One answer in an [RsvpChoice]: its label and how many gave it.
typedef RsvpOption<T> = ({T value, String label, int count});

/// "Are you in?": the answers side by side in a field-coloured track, the
/// picked one filled turf. Tapping the picked answer again clears it.
/// [onChanged] null disables it (e.g. while saving).
class RsvpChoice<T> extends StatelessWidget {
  const RsvpChoice({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<RsvpOption<T>> options;
  final T? selected;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.field,
        borderRadius: BorderRadius.circular(controlRadius),
      ),
      // Equal heights when a long answer wraps.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: _option(context, c, options[i])),
            ],
          ],
        ),
      ),
    );
  }

  Widget _option(BuildContext context, AppColors c, RsvpOption<T> o) {
    final on = o.value == selected;
    final fg = on ? c.onAccent : c.ink2;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: on,
      button: true,
      child: Material(
        color: on ? c.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(controlRadius - 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(controlRadius - 2),
          onTap: onChanged == null
              ? null
              : () => onChanged!(on ? null : o.value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (on) ...[
                        Icon(Icons.check, size: 16, color: fg),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          o.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                            color: fg,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${o.count}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: on ? c.onAccent : c.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How a group of answers reads in [RsvpResponses]: yes (turf), other
/// answers (ink) and no reply yet (muted).
enum RsvpTone { yes, other, none }

/// One group of names in [RsvpResponses], e.g. "Going" and who.
typedef RsvpGroup = ({String label, List<String> names, RsvpTone tone});

/// Who answered what: each group's label and count, then every name. The
/// first "yes" group leads with a few initials.
class RsvpResponses extends StatelessWidget {
  const RsvpResponses({super.key, required this.groups});

  final List<RsvpGroup> groups;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < groups.length; i++)
          Container(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10, bottom: 10),
            decoration: BoxDecoration(
              border: i == 0 ? null : Border(top: BorderSide(color: c.border)),
            ),
            child: _group(c, groups[i]),
          ),
      ],
    );
  }

  Widget _group(AppColors c, RsvpGroup g) {
    final (labelColor, nameColor) = switch (g.tone) {
      RsvpTone.yes => (c.accentInk, c.ink2),
      RsvpTone.other => (c.ink2, c.ink2),
      RsvpTone.none => (c.muted, c.muted),
    };
    final names = Text(
      g.names.isEmpty ? 'Nobody yet.' : g.names.join(', '),
      style: TextStyle(fontSize: 13, height: 1.4, color: nameColor),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${g.label} (${g.names.length})',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 6),
        if (g.tone == RsvpTone.yes && g.names.isNotEmpty)
          Row(
            children: [
              _Faces(names: g.names.take(4).toList()),
              const SizedBox(width: 10),
              Expanded(child: names),
            ],
          )
        else
          names,
      ],
    );
  }
}

/// Overlapping initials, for the people going.
class _Faces extends StatelessWidget {
  const _Faces({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    const size = 30.0;
    return SizedBox(
      width: size + (names.length - 1) * (size - 8),
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < names.length; i++)
            Positioned(
              left: i * (size - 8),
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == 0 ? c.accentSoft : c.field,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.card, width: 2),
                ),
                child: Text(
                  initialsOf(names[i]),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: i == 0 ? c.accentInk : c.ink2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The user's answer on a schedule row: "Going" in turf, other answers
/// neutral, and "Needs RSVP" in amber when [needsRsvp] and unanswered.
class RsvpStatusPill extends StatelessWidget {
  const RsvpStatusPill({
    super.key,
    required this.status,
    required this.type,
    this.needsRsvp = false,
    this.strong = false,
  });

  final RsvpStatus? status;
  final EventType type;
  final bool needsRsvp;

  /// "Needs RSVP" in solid amber, e.g. on a row already tinted amber.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) {
      return needsRsvp
          ? NeedsYouPill('Needs RSVP', strong: strong)
          : const SizedBox.shrink();
    }
    final c = AppColors.of(context);
    final going = s == RsvpStatus.going;
    final fg = going ? c.accentInk : (s == RsvpStatus.maybe ? c.ink2 : c.muted);
    return Container(
      constraints: const BoxConstraints(maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: going ? c.accentSoft : c.field,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (going) ...[
            Icon(Icons.check, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              // Tournament answers are long; rows show the short one.
              type == EventType.tournament && !going
                  ? s.label
                  : s.labelFor(type),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
