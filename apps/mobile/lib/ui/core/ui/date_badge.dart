import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../themes/theme.dart';

/// Month over day, e.g. "NOV / 02", for event rows. A [cancelled] event
/// gets a quiet grey badge (the row says "Cancelled" in words too).
///
/// The badge is a fixed-size tile: its text is sized from [size] and does
/// not follow the text scale (the date is also read aloud in full).
///
/// Website counterpart: `DateBadge` (apps/web).
class DateBadge extends StatelessWidget {
  const DateBadge({
    super.key,
    required this.date,
    this.size = 40,
    this.cancelled = false,
  });

  final DateTime date;
  final double size;
  final bool cancelled;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final fill = cancelled ? c.field : c.accentSoft;
    final ink = cancelled ? c.ink2 : c.accentInk;
    return Semantics(
      label: DateFormat.MMMMd().format(date),
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size + 4,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(size * 0.25),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateFormat.MMM().format(date).toUpperCase(),
              softWrap: false,
              overflow: TextOverflow.clip,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: size * 0.2,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: ink,
              ),
            ),
            Text(
              DateFormat('dd').format(date),
              softWrap: false,
              overflow: TextOverflow.clip,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontFamily: scoreFont,
                fontSize: size * 0.5,
                height: 1.0,
                fontWeight: FontWeight.w800,
                color: ink,
                decoration: cancelled ? TextDecoration.lineThrough : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
