import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../themes/theme.dart';

/// Month over day, e.g. "NOV / 02", for event rows. A [cancelled] event
/// gets a quiet grey badge (the row says "Cancelled" in words too).
///
/// The badge is [size] wide and at least [size] + 4 tall; its text follows
/// the text scale up to 1.5x (the month is never under 11 px), and the
/// tile grows taller to hold it. The date is also read aloud in full.
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

  static TextScaler _scaler(BuildContext context) =>
      MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.5);

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
        constraints: BoxConstraints(minHeight: size + 4),
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
              textScaler: _scaler(context),
              style: TextStyle(
                fontSize: math.max(11, size * 0.25),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: ink,
              ),
            ),
            Text(
              DateFormat('dd').format(date),
              softWrap: false,
              overflow: TextOverflow.clip,
              textScaler: _scaler(context),
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
