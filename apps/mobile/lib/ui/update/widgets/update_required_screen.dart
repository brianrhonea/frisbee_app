import 'package:flutter/material.dart';

import '../../core/themes/theme.dart';
import '../../core/ui/app_button.dart';
import '../../core/ui/brand.dart';

/// The blocking screen for a build below `meta/flags.minBuild` (#6): what
/// happened, one button to the store, nothing else. It can't be dismissed.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key, required this.onUpdate});

  /// Opens the store listing.
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpace.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: AppLogo(size: 72)),
                    const SizedBox(height: AppSpace.xl),
                    Semantics(
                      header: true,
                      child: Text(
                        'Update required',
                        textAlign: TextAlign.center,
                        style: AppText.heading3.copyWith(color: c.ink),
                      ),
                    ),
                    const SizedBox(height: AppSpace.md),
                    Text(
                      'This version of $appName is out of date and can no '
                      'longer be used. Update the app to keep going. Your '
                      'teams, messages and schedule are all still there.',
                      textAlign: TextAlign.center,
                      style: AppText.body.copyWith(color: c.ink2),
                    ),
                    const SizedBox(height: AppSpace.xl),
                    AppButton.primary(
                      'Update the app',
                      icon: Icons.system_update_alt,
                      size: AppButtonSize.large,
                      expand: true,
                      onPressed: onUpdate,
                    ),
                    const SizedBox(height: AppSpace.lg),
                    Text(
                      'Your version: $appVersion',
                      textAlign: TextAlign.center,
                      style: AppText.caption.copyWith(color: c.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
