import 'package:flutter/material.dart';

import '../../../utils/password_policy.dart';
import '../../core/themes/theme.dart';

/// Under a new password: a strength bar and the requirements, ticked as
/// they're met.
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller,
    builder: (context, value, _) {
      final c = AppColors.of(context);
      final password = value.text;
      final strength = PasswordStrength.values.indexOf(
        PasswordPolicy.strength(password),
      );
      final small = TextStyle(fontSize: 12, color: c.muted);
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (password.isNotEmpty)
              Row(
                children: [
                  // Four segments, filled up to the strength.
                  for (var i = 0; i < PasswordStrength.values.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: i <= strength ? c.accent : c.border2,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 10),
                  Text(
                    PasswordStrength.values[strength].label,
                    style: small.copyWith(
                      color: strength >= 2 ? c.accentInk : c.ink2,
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
                        color: r.met ? c.accent : c.muted,
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
