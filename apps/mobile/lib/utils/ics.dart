import 'dart:convert';

import '../domain/models/team_event.dart';

/// iCalendar (RFC 5545) for "Add to calendar": one event as a file that
/// Outlook, Apple Calendar and Google Calendar open. The same format as
/// `packages/shared/src/ical.ts`, which the API's subscription feed uses:
/// CRLF lines, escaped text, lines folded at 75 octets.
abstract final class Ics {
  /// RFC 5545 §3.3.11: backslash, semicolon, comma and newlines.
  static String text(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll(RegExp(r'\r\n|\r|\n'), r'\n');

  /// 20261115T170000Z
  static String date(DateTime d) {
    final u = d.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}'
        'T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }

  /// RFC 5545 §3.1: lines over 75 octets go on after a CRLF and a space,
  /// never splitting a character.
  static String fold(String line) {
    if (utf8.encode(line).length <= 75) return line;
    final out = <String>[];
    var current = StringBuffer();
    var size = 0;
    for (final rune in line.runes) {
      final ch = String.fromCharCode(rune);
      final n = utf8.encode(ch).length;
      if (size + n > (out.isEmpty ? 75 : 74)) {
        out.add(current.toString());
        current = StringBuffer();
        size = 0;
      }
      current.write(ch);
      size += n;
    }
    out.add(current.toString());
    return out.join('\r\n ');
  }

  /// [event] as a calendar file. [uid] stays the same each time it's
  /// exported, so adding it again updates it instead of duplicating it.
  static String event(
    TeamEvent event, {
    required String uid,
    String? description,
    DateTime? now,
  }) {
    final end = event.endsAt ?? event.startsAt.add(const Duration(hours: 1));
    final notes = description ?? event.notes;
    final lines = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Stall 10//Calendar//EN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'BEGIN:VEVENT',
      'UID:${text(uid)}',
      'DTSTAMP:${date(now ?? DateTime.now())}',
      'DTSTART:${date(event.startsAt)}',
      'DTEND:${date(end)}',
      'SUMMARY:${text(event.title)}',
      if (event.location.isNotEmpty) 'LOCATION:${text(event.location)}',
      if (notes.isNotEmpty) 'DESCRIPTION:${text(notes)}',
      'END:VEVENT',
      'END:VCALENDAR',
    ];
    return '${lines.map(fold).join('\r\n')}\r\n';
  }

  /// A file name for [title]: "Track session.ics".
  static String fileName(String title) {
    final clean = title.replaceAll(RegExp(r'[^\w -]+'), '').trim();
    final name = clean.isEmpty
        ? 'event'
        : clean.substring(0, clean.length.clamp(0, 60));
    return '$name.ics';
  }
}
