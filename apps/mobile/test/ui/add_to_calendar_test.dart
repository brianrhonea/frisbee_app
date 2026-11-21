import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/services/device_calendar_service.dart';
import 'package:frisbee_app/domain/models/team_event.dart';
import 'package:frisbee_app/ui/calendar/widgets/add_to_calendar.dart';
import 'package:provider/provider.dart';

/// Records what "Add to calendar" asks of the device (F35).
class _FakeDeviceCalendar implements DeviceCalendarService {
  _FakeDeviceCalendar(this.result);

  final CalendarAddResult result;
  final added = <CalendarEntry>[];
  final shared =
      <({String ics, String fileName, String subject, String? text})>[];

  @override
  Future<CalendarAddResult> addEvent(CalendarEntry entry) async {
    added.add(entry);
    return result;
  }

  @override
  Future<void> shareIcs({
    required String ics,
    required String fileName,
    required String subject,
    String? text,
    Rect? origin,
  }) async {
    shared.add((ics: ics, fileName: fileName, subject: subject, text: text));
  }
}

// "Add to calendar" opens the phone's new-event editor (the person picks
// the calendar), and shares an .ics file only where there's no editor.
void main() {
  final event = TeamEvent(
    id: 'e1',
    title: 'Track session',
    startsAt: DateTime.utc(2026, 11, 15, 17),
    location: 'High school track',
    notes: 'Bring spikes',
  );

  Future<_FakeDeviceCalendar> tapAdd(
    WidgetTester tester,
    CalendarAddResult result, {
    TeamEvent? of,
    String? description,
    bool asIcon = false,
  }) async {
    final calendar = _FakeDeviceCalendar(result);
    await tester.pumpWidget(
      Provider<DeviceCalendarService>.value(
        value: calendar,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: AddToCalendarButton(
                event: of ?? event,
                uid: 'team-t1-e1@stall10.app',
                description: description,
                asIcon: asIcon,
              ),
            ),
          ),
        ),
      ),
    );
    if (asIcon) {
      await tester.tap(find.byTooltip('Add to calendar'));
    } else {
      await tester.tap(find.text('Add to calendar'));
    }
    await tester.pumpAndSettle();
    return calendar;
  }

  testWidgets('opens the editor with the event, an hour long by default', (
    tester,
  ) async {
    final calendar = await tapAdd(tester, CalendarAddResult.added);
    final entry = calendar.added.single;
    expect(entry.title, 'Track session');
    expect(entry.start, DateTime.utc(2026, 11, 15, 17));
    expect(entry.end, DateTime.utc(2026, 11, 15, 18));
    expect(entry.location, 'High school track');
    expect(entry.notes, 'Bring spikes');
    // Added: no file as well.
    expect(calendar.shared, isEmpty);
  });

  testWidgets('keeps the end and uses the description over the notes', (
    tester,
  ) async {
    final calendar = await tapAdd(
      tester,
      CalendarAddResult.added,
      of: TeamEvent(
        id: 'e2',
        title: 'Hat tournament',
        startsAt: DateTime.utc(2026, 11, 21, 15),
        endsAt: DateTime.utc(2026, 11, 21, 23),
      ),
      description: 'Pool play, then brackets',
      asIcon: true,
    );
    final entry = calendar.added.single;
    expect(entry.end, DateTime.utc(2026, 11, 21, 23));
    expect(entry.location, '');
    expect(entry.notes, 'Pool play, then brackets');
  });

  testWidgets('Share sends the event as a calendar file with what and when, '
      'no shared calendar needed', (tester) async {
    final calendar = await tapAdd(tester, CalendarAddResult.added);
    calendar.added.clear();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(calendar.added, isEmpty);
    final s = calendar.shared.single;
    expect(s.subject, 'Track session');
    expect(s.fileName, endsWith('.ics'));
    expect(s.ics, contains('SUMMARY:Track session'));
    expect(s.text, startsWith('Track session · '));
    expect(s.text, endsWith(' · High school track'));
  });

  testWidgets('closing the editor shares nothing', (tester) async {
    final calendar = await tapAdd(tester, CalendarAddResult.cancelled);
    expect(calendar.added, hasLength(1));
    expect(calendar.shared, isEmpty);
  });

  testWidgets('with no calendar editor, shares the .ics file instead', (
    tester,
  ) async {
    final calendar = await tapAdd(tester, CalendarAddResult.unavailable);
    final file = calendar.shared.single;
    expect(file.fileName, 'Track session.ics');
    expect(file.subject, 'Track session');
    expect(file.ics, contains('UID:team-t1-e1@stall10.app\r\n'));
    expect(file.ics, contains('DTSTART:20261115T170000Z\r\n'));
    expect(file.ics, contains('LOCATION:High school track\r\n'));
  });
}
