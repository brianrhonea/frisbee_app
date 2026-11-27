import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/moderation/moderation_repository.dart';
import '../../../data/services/crash_reporting.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/brand.dart';
import '../../core/ui/confirm_dialog.dart';

/// "Stall 10 v0.0.60" at the foot of Settings. For Stall 10 staff, and in
/// debug builds, a long press offers "Send test crash", to prove crash
/// reports arrive (Crashlytics). Nobody else sees any difference.
class VersionLabel extends StatelessWidget {
  const VersionLabel({super.key, this.debug = kDebugMode});

  /// A debug build (a parameter so tests can check a release one).
  final bool debug;

  Future<void> _offerTestCrash(BuildContext context) async {
    if (await confirmDialog(
      context,
      title: 'Send test crash?',
      message: 'This closes the app on purpose so a crash report is sent.',
      confirmLabel: 'Send test crash',
      destructive: true,
    )) {
      CrashReporting.sendTestCrash();
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = Text(
      '$appName v$appVersion',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, color: AppColors.of(context).muted),
    );
    final moderation = _maybe<ModerationRepository>(context);
    final uid = _maybe<AuthRepository>(context)?.currentUser?.uid;
    if (debug || (moderation != null && uid != null)) {
      return StreamBuilder<bool>(
        stream: moderation != null && uid != null
            ? moderation.watchStaff(uid)
            : null,
        builder: (context, staff) => GestureDetector(
          onLongPress: debug || staff.data == true
              ? () => _offerTestCrash(context)
              : null,
          child: label,
        ),
      );
    }
    return label;
  }
}

T? _maybe<T>(BuildContext context) {
  try {
    return context.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}
