import 'package:flutter/material.dart';

/// Every time picker in the app: it opens on the hour and minute boxes,
/// with the hour focused so the time can be typed straight away, and the
/// clock icon in its corner switches to the dial for picking by hand.
Future<TimeOfDay?> showTypedTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  String? helpText,
}) => showTimePicker(
  context: context,
  initialTime: initialTime,
  helpText: helpText,
  initialEntryMode: TimePickerEntryMode.input,
  builder: (context, child) => _FocusHour(child: child!),
);

/// Flutter's picker only focuses the hour box after switching from the
/// dial; this focuses it when the picker opens (the hour is its first
/// field).
class _FocusHour extends StatefulWidget {
  const _FocusHour({required this.child});

  final Widget child;

  @override
  State<_FocusHour> createState() => _FocusHourState();
}

class _FocusHourState extends State<_FocusHour> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      EditableTextState? first;
      void find(Element e) {
        if (first != null) return;
        if (e is StatefulElement && e.state is EditableTextState) {
          first = e.state as EditableTextState;
          return;
        }
        e.visitChildElements(find);
      }

      context.visitChildElements(find);
      first?.requestKeyboard();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
