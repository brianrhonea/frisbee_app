import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/services/device_calendar_service.dart';
import '../../../domain/models/team_event.dart';
import '../../../utils/ics.dart';

/// "Add to calendar": opens the phone's new-event editor filled in with
/// [event], where the person picks which calendar it goes on and saves.
/// Where there's no editor (no calendar app, or the plugin fails) it shares
/// [event] as an .ics file instead; [uid] is stable per event, so adding
/// that file twice updates it.
Future<void> addToCalendar(
  BuildContext context,
  TeamEvent event, {
  required String uid,
  String? description,
}) async {
  final calendar = _service(context);
  final box = context.findRenderObject() as RenderBox?;
  // iPad anchors the share sheet here.
  final origin = box == null || !box.hasSize
      ? null
      : box.localToGlobal(Offset.zero) & box.size;
  final notes = description ?? event.notes;
  final result = await calendar.addEvent(
    CalendarEntry(
      title: event.title,
      start: event.startsAt,
      end: Ics.endOf(event),
      location: event.location,
      notes: notes,
    ),
  );
  if (result != CalendarAddResult.unavailable) return;
  await calendar.shareIcs(
    ics: Ics.event(event, uid: uid, description: description),
    fileName: Ics.fileName(event.title),
    subject: event.title,
    origin: origin,
  );
}

/// The app's [DeviceCalendarService], or the real one where none is
/// provided (screens pumped without it in tests).
DeviceCalendarService _service(BuildContext context) {
  try {
    return context.read<DeviceCalendarService>();
  } on ProviderNotFoundException {
    return const DeviceCalendarService();
  }
}

/// An app bar or sheet button for [addToCalendar].
class AddToCalendarButton extends StatelessWidget {
  const AddToCalendarButton({
    super.key,
    required this.event,
    required this.uid,
    this.description,
    this.asIcon = false,
  });

  final TeamEvent event;
  final String uid;
  final String? description;

  /// An icon (app bars) rather than a labelled button (sheets).
  final bool asIcon;

  @override
  Widget build(BuildContext context) {
    void add() =>
        addToCalendar(context, event, uid: uid, description: description);
    return asIcon
        ? IconButton(
            tooltip: 'Add to calendar',
            icon: const Icon(Icons.event_available_outlined),
            onPressed: add,
          )
        : OutlinedButton.icon(
            onPressed: add,
            icon: const Icon(Icons.event_available_outlined),
            label: const Text('Add to calendar'),
          );
  }
}
