import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../themes/theme.dart';

/// Whether shortcuts use ⌘ (Apple keyboards) rather than Ctrl.
bool get usesCommandKey =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// "⌘K" on a Mac, "Ctrl K" elsewhere, for [key] pressed with the
/// platform's shortcut modifier.
String shortcutLabel(String key) => usesCommandKey ? '⌘$key' : 'Ctrl $key';

/// Whether this device likely has a keyboard worth hinting at: desktops
/// and wide screens, not phones.
bool showsKeyHints(BuildContext context) =>
    switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => true,
      _ => false,
    } ||
    kIsWeb;

/// A keyboard shortcut drawn as a key cap, e.g. next to the search box.
class KeyHint extends StatelessWidget {
  const KeyHint(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: ShapeDecoration(
        color: c.card,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: c.border),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: c.muted,
          height: 1.3,
        ),
      ),
    );
  }
}
