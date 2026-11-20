import 'dart:convert';
import 'dart:io' show Platform;

import 'package:add_2_calendar/add_2_calendar.dart' as native;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// One event to add to the person's own calendar: the same fields the
/// website's Google Calendar and Outlook links carry
/// (`packages/shared/src/calendar_links.ts`). Times are instants, shown in
/// the device's time zone.
@immutable
class CalendarEntry {
  const CalendarEntry({
    required this.title,
    required this.start,
    required this.end,
    this.location = '',
    this.notes = '',
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final String location;
  final String notes;
}

/// What happened to an "Add to calendar".
enum CalendarAddResult {
  /// Saved (iOS), or the calendar app's new-event screen opened (Android,
  /// which doesn't say whether the person then saved it).
  added,

  /// The person closed the event editor without saving (iOS), or iOS
  /// refused calendar access (iOS 15–16 ask first; it can't tell us which).
  cancelled,

  /// No calendar editor here (no calendar app, an unsupported platform or
  /// the plugin failed): share the .ics file instead.
  unavailable,
}

/// The device calendar: the system's "new event" editor, where the person
/// picks the calendar and saves (iOS EKEventEditViewController, needing no
/// calendar access from iOS 17; Android's calendar insert screen, needing
/// no permission), and sharing an .ics file when there's no editor.
class DeviceCalendarService {
  const DeviceCalendarService();

  /// Opens the system's new-event editor filled in with [entry].
  Future<CalendarAddResult> addEvent(CalendarEntry entry) async {
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) {
      return CalendarAddResult.unavailable;
    }
    try {
      // add_2_calendar is pinned at 3.0.1 (3.1 needs Android Gradle Plugin
      // 9). On iOS 17+ that version opens the editor but never answers,
      // so this future can stay pending; nothing waits on it (the button
      // has no busy state), and the editor saves on its own.
      final ok = await native.Add2Calendar.addEvent2Cal(
        native.Event(
          title: entry.title,
          description: entry.notes.isEmpty ? null : entry.notes,
          location: entry.location.isEmpty ? null : entry.location,
          startDate: entry.start,
          endDate: entry.end,
          // Null: the device's own zone (events are fixed instants).
        ),
      );
      if (ok) return CalendarAddResult.added;
      // Android says false only when no app takes new events; iOS when the
      // editor was cancelled (or access refused).
      return Platform.isAndroid
          ? CalendarAddResult.unavailable
          : CalendarAddResult.cancelled;
    } on PlatformException {
      return CalendarAddResult.unavailable;
    } on MissingPluginException {
      return CalendarAddResult.unavailable;
    }
  }

  /// Shares [ics] as a calendar file named [fileName], which the share
  /// sheet offers to Apple Calendar, Outlook, Google Calendar or Files.
  /// [origin] anchors the sheet on iPad.
  Future<void> shareIcs({
    required String ics,
    required String fileName,
    required String subject,
    Rect? origin,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            utf8.encode(ics),
            mimeType: 'text/calendar',
            name: fileName,
          ),
        ],
        fileNameOverrides: [fileName],
        subject: subject,
        sharePositionOrigin: origin,
      ),
    );
  }
}
