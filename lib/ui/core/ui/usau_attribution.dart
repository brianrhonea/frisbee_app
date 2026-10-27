import 'package:flutter/material.dart';

class UsauAttribution extends StatelessWidget {
  const UsauAttribution({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(
      'Data sourced from USA Ultimate (usaultimate.org). '
      'Not affiliated with or endorsed by USA Ultimate.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
