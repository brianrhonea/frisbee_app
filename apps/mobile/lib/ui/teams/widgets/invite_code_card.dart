import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/invite_code.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart' show Eyebrow;
import '../view_models/invite_code_viewmodel.dart';

/// The team's invite code for owners, coaches and captains. Hidden until
/// asked for; then a new code every 30 seconds, with a countdown.
class InviteCodeCard extends StatelessWidget {
  const InviteCodeCard({super.key, required this.viewModel});

  final InviteCodeViewModel viewModel;

  static final _rotateSeconds = InviteCode.rotateEvery.inSeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final code = viewModel.code;
        return Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Eyebrow(
                        'Invite code',
                        color: AppColors.of(context).accentInk,
                      ),
                      if (!viewModel.showing) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Players join with a code that changes every '
                          '$_rotateSeconds seconds. Show it when someone is '
                          'ready to type it in.',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (viewModel.error case final e?)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              errorMessage(e),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                      ] else if (code == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else ...[
                        SelectableText(
                          code,
                          style: TextStyle(
                            fontFamily: scoreFont,
                            fontSize: 36,
                            height: 1.1,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w800,
                            color: AppColors.of(context).ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: viewModel.secondsLeft / _rotateSeconds,
                          minHeight: 3,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'New code in ${viewModel.secondsLeft}s',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (!viewModel.showing)
                  FilledButton.tonal(
                    onPressed: viewModel.show,
                    child: const Text('Show code'),
                  )
                else ...[
                  IconButton(
                    tooltip: 'Copy',
                    icon: const Icon(Icons.copy),
                    onPressed: code == null
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: code));
                            if (context.mounted) {
                              showSnackBar(context, 'Invite code copied');
                            }
                          },
                  ),
                  IconButton(
                    tooltip: 'Hide code',
                    icon: const Icon(Icons.visibility_off_outlined),
                    onPressed: viewModel.hide,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
