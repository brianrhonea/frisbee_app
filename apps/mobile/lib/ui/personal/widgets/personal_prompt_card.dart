import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/routes.dart';
import '../view_models/personal_prompt_viewmodel.dart';

/// Suggests adding personal details; hidden once given or dismissed.
class PersonalPromptCard extends StatelessWidget {
  const PersonalPromptCard({super.key, required this.viewModel});

  final PersonalPromptViewModel viewModel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      if (!viewModel.visible) return const SizedBox.shrink();
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Complete your details',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Add your legal name, birthday and contact details. Only '
                  'you can see them, and we keep them encrypted.',
                  style: theme.textTheme.bodyMedium,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: viewModel.dismiss,
                      child: const Text('Not now'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => context.push(Routes.settingsPersonal),
                      child: const Text('Add details'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
