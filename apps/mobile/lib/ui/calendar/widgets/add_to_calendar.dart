import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../domain/models/team_event.dart';
import '../../../utils/ics.dart';

/// "Add to calendar": shares [event] as an .ics file, which the share sheet
/// offers to Apple Calendar, Outlook, Google Calendar or Files. [uid] is
/// stable per event, so adding it twice updates it.
Future<void> addToCalendar(
  BuildContext context,
  TeamEvent event, {
  required String uid,
  String? description,
}) async {
  final box = context.findRenderObject() as RenderBox?;
  final ics = Ics.event(event, uid: uid, description: description);
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          utf8.encode(ics),
          mimeType: 'text/calendar',
          name: Ics.fileName(event.title),
        ),
      ],
      fileNameOverrides: [Ics.fileName(event.title)],
      subject: event.title,
      // iPad anchors the sheet here.
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
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
