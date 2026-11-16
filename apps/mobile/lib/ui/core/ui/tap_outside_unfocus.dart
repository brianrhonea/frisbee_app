import 'package:flutter/material.dart';

/// Closes the keyboard when someone taps anywhere outside the text field
/// they're typing in, as people expect on phones. Flutter only does this
/// for a mouse on mobile; a finger leaves the field focused and the
/// keyboard stuck open.
///
/// Wraps the whole app, above every page, dialog and sheet. A send button
/// that should keep the keyboard open (a chat or comment bar) sits in a
/// [TextFieldTapRegion] with its field.
class TapOutsideUnfocus extends StatelessWidget {
  const TapOutsideUnfocus({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Actions(
    actions: <Type, Action<Intent>>{
      EditableTextTapOutsideIntent:
          CallbackAction<EditableTextTapOutsideIntent>(
            onInvoke: (intent) {
              intent.focusNode.unfocus();
              return null;
            },
          ),
    },
    child: child,
  );
}

/// Takes the focus off whatever text field has it, so the keyboard closes
/// and a page or sheet that opens next doesn't hand it back on closing.
void dropKeyboard() => FocusManager.instance.primaryFocus?.unfocus();
