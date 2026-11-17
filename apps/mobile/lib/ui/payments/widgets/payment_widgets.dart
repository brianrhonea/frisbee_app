import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/repositories/payment/payment_repository.dart';
import '../../../domain/models/payments.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/view_model_host.dart';
import '../view_models/payments_viewmodels.dart';

/// Stripe's pages open in the browser: entry fees are for real-world
/// events, which Apple and Google let apps take payment for outside
/// in-app purchase.
Future<bool> openStripePage(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// Reloads [load] each time the app comes back to the front: the user is
/// returning from Stripe's page in the browser.
class _OnResume extends StatefulWidget {
  const _OnResume({required this.load, required this.child});

  final VoidCallback load;
  final Widget child;

  @override
  State<_OnResume> createState() => _OnResumeState();
}

class _OnResumeState extends State<_OnResume> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onResume: () => widget.load());
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The app's payments, or null where none is provided (payments are off).
PaymentRepository? _payments(BuildContext context) {
  try {
    return context.read<PaymentRepository>();
  } on ProviderNotFoundException {
    return null;
  }
}

void _showError(BuildContext context, Object? error) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(errorMessage(error))));

/// The host owner's "Get paid online" card. Shows nothing until the server
/// says online payments are available (and the user is the owner).
class PayoutsCard extends StatelessWidget {
  const PayoutsCard({super.key, required this.teamId, this.open});

  final String teamId;

  /// Opens Stripe's page; tests pass a fake.
  final OpenPage? open;

  @override
  Widget build(BuildContext context) {
    final payments = _payments(context);
    if (payments == null) return const SizedBox.shrink();
    return ViewModelHost<PayoutsViewModel>(
      create: (c) => PayoutsViewModel(
        payments: payments,
        teamId: teamId,
        open: open ?? openStripePage,
      ),
      builder: (context, vm) => _OnResume(
        load: vm.load.execute,
        child: ListenableBuilder(
          listenable: Listenable.merge([vm, vm.connect]),
          builder: (context, _) => _payouts(context, vm),
        ),
      ),
    );
  }

  Widget _payouts(BuildContext context, PayoutsViewModel vm) {
    final a = vm.account;
    if (!a.available) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final (title, body, action) = switch (a.status) {
      PayoutStatus.none => (
        'Take payments online',
        'Let teams and players pay their fees in Stall 10 instead of '
            'collecting them yourself. Payments go to your own Stripe '
            'account. Stripe keeps its card fee and Stall 10 keeps '
            '${a.feeLabel} of each payment.',
        'Set up with Stripe',
      ),
      PayoutStatus.pending => (
        'Finish setting up payments',
        'Stripe still needs a few details before you can take payments.',
        'Continue with Stripe',
      ),
      PayoutStatus.ready => (
        'Online payments are on',
        'Teams and players can pay their fees in Stall 10. Refunds and '
            'payouts are in your Stripe Dashboard. Stall 10 keeps '
            '${a.feeLabel} of each payment.',
        null,
      ),
    };
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  a.status == PayoutStatus.ready
                      ? Icons.check_circle_outline
                      : Icons.payments_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body),
            if (action != null) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: vm.connect.running
                    ? null
                    : () async {
                        await vm.connect.execute();
                        if (context.mounted && vm.connect.error) {
                          _showError(context, vm.connect.result);
                        }
                      },
                child: Text(action),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Pay $400 online", for a team's bid or spot fee ([teamId]) or the
/// user's own entry fee. Shows nothing unless the host takes payments
/// through Stall 10 and it isn't paid yet.
class PayOnlineButton extends StatelessWidget {
  const PayOnlineButton({
    super.key,
    required this.tournamentId,
    this.teamId,
    this.open,
  });

  final String tournamentId;
  final String? teamId;
  final OpenPage? open;

  @override
  Widget build(BuildContext context) {
    final payments = _payments(context);
    if (payments == null) return const SizedBox.shrink();
    return ViewModelHost<PayOnlineViewModel>(
      create: (c) => PayOnlineViewModel(
        payments: payments,
        tournamentId: tournamentId,
        teamId: teamId,
        open: open ?? openStripePage,
      ),
      builder: (context, vm) => _OnResume(
        load: vm.load.execute,
        child: ListenableBuilder(
          listenable: Listenable.merge([vm, vm.pay]),
          builder: (context, _) {
            final o = vm.options;
            if (o == null || !vm.canPay) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.icon(
                    onPressed: vm.pay.running
                        ? null
                        : () async {
                            await vm.pay.execute();
                            if (context.mounted && vm.pay.error) {
                              _showError(context, vm.pay.result);
                            }
                          },
                    icon: const Icon(Icons.lock_outline),
                    label: Text('Pay ${centsLabel(o.amountCents)} online'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Secure checkout by Stripe. It shows as paid here once '
                    'Stripe confirms it.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
