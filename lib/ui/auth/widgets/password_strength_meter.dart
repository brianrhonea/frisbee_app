import 'package:flutter/material.dart';

import '../../../utils/password_policy.dart';

/// Under a new password: a strength bar and the requirements, ticked as
/// they're met.
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller,
    builder: (context, value, _) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final password = value.text;
      final strength = PasswordPolicy.strength(password);
      final color = switch (strength) {
        PasswordStrength.weak => colors.error,
        PasswordStrength.fair => Colors.orange,
        PasswordStrength.good => Colors.lightGreen.shade700,
        PasswordStrength.strong => Colors.green.shade700,
      };
      final small = theme.textTheme.bodySmall;
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (password.isNotEmpty)
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: (strength.index + 1) / 4,
                        minHeight: 4,
                        color: color,
                        backgroundColor: colors.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    strength.label,
                    style: small?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              children: [
                for (final r in PasswordPolicy.checklist(password))
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        r.met ? Icons.check_circle : Icons.circle_outlined,
                        size: 14,
                        color: r.met ? Colors.green.shade700 : colors.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(r.label, style: small),
                    ],
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
