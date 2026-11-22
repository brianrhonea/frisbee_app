import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/legal_links.dart';
import '../../../domain/models/agreement.dart';
import '../../core/ui/error_message.dart';
import '../view_models/agree_terms_viewmodel.dart';
import 'auth_layout.dart';

/// Read and agree to the Community Guidelines and Terms of Service, before
/// anything else (AgreeTerms on the website).
class AgreeTermsScreen extends StatefulWidget {
  const AgreeTermsScreen({super.key, required this.viewModel});

  final AgreeTermsViewModel viewModel;

  @override
  State<AgreeTermsScreen> createState() => _AgreeTermsScreenState();
}

class _AgreeTermsScreenState extends State<AgreeTermsScreen> {
  AgreeTermsViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.agree.addListener(_onResult);
  }

  @override
  void dispose() {
    vm.agree.removeListener(_onResult);
    super.dispose();
  }

  void _onResult() {
    if (vm.agree.error) {
      showErrorSnackBar(context, vm.agree.result);
      vm.agree.clearResult();
    }
  }

  Future<void> _open(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Couldn't open $url")));
    }
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: 'Before you start',
    subtitle:
        'Stall 10 is for players, teams and families. Everyone agrees to '
        'keep it that way.',
    child: ListenableBuilder(
      listenable: Listenable.merge([vm, vm.agree, vm.signOut]),
      builder: (context, _) {
        final busy = vm.agree.running || vm.signOut.running;
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final p in agreementPoints)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(p)),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            // A column, not a Wrap: AuthLayout sizes by intrinsic height.
            for (final (label, url) in [
              ('Read the Community Guidelines', LegalLinks.guidelines),
              ('Read the Terms of Service', LegalLinks.terms),
              ('Read the Privacy Policy', LegalLinks.privacy),
            ])
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => _open(url),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(label),
                ),
              ),
            CheckboxListTile(
              key: const Key('agree-terms'),
              value: vm.checked,
              onChanged: busy ? null : (v) => vm.checked = v ?? false,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                "I've read and agree to the Community Guidelines and Terms "
                'of Service',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: vm.checked && !busy ? vm.agree.execute : null,
              child: vm.agree.running
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Continue'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: busy ? null : vm.signOut.execute,
              child: const Text('Sign out'),
            ),
          ],
        );
      },
    ),
  );
}
