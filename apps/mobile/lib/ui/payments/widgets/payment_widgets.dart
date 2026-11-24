import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/repositories/payment/payment_repository.dart';
import '../../../data/services/payment_sheet_service.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/payments.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/view_model_host.dart';
import '../view_models/payments_viewmodels.dart';
import 'payouts_setup_screen.dart';

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
PaymentSheetService? _sheet(BuildContext context) {
  try {
    return context.read<PaymentSheetService?>();
  } on ProviderNotFoundException {
    return null;
  }
}

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

/// "Refund" for a fee paid online (the event's organizers): asks first,
/// saying what comes back, then shows any error. The payment record says
/// "Refunded through Stall 10" once it's done.
class RefundButton extends StatelessWidget {
  const RefundButton({
    super.key,
    required this.name,
    required this.amountCents,
    required this.running,
    required this.onRefund,
    required this.result,
  });

  final String name;
  final int amountCents;
  final bool running;
  final Future<void> Function() onRefund;
  final Result<void>? Function() result;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: running
        ? null
        : () async {
            final ok = await confirmDialog(
              context,
              title: 'Refund ${centsLabel(amountCents)} to $name?',
              message:
                  '$refundPolicyNote If Stall 10 already sent you the fee, '
                  'it comes back out of your payouts.',
              confirmLabel: 'Refund',
              destructive: true,
            );
            if (!ok || !context.mounted) return;
            await onRefund();
            if (!context.mounted) return;
            if (result() case Error(:final error)) _showError(context, error);
          },
    child: const Text('Refund'),
  );
}

/// "We'll pay another way" (a school's check or PO), so the host sees it's
/// coming; or, once said, a way to take it back.
Widget _offline(BuildContext context, PayOnlineViewModel vm) {
  if (!vm.canPayOffline) return const SizedBox.shrink();
  final o = vm.options!;
  final small = Theme.of(context).textTheme.bodySmall;
  Future<void> run(bool offline) async {
    await vm.payOffline.execute(offline);
    if (context.mounted && vm.payOffline.error) {
      _showError(context, vm.payOffline.result);
    }
  }

  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: ListenableBuilder(
      listenable: vm.payOffline,
      builder: (context, _) => vm.payingAnotherWay
          ? Row(
              children: [
                Expanded(
                  child: Text(
                    "You told the host you'll pay another way. Ask them to "
                    'mark it paid when it arrives.',
                    style: small,
                  ),
                ),
                TextButton(
                  onPressed: vm.payOffline.running ? null : () => run(false),
                  child: const Text('Undo'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton(
                  key: const Key('pay-another-way'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: vm.payOffline.running ? null : () => run(true),
                  child: const Text("We'll pay another way"),
                ),
                if (!o.online || o.reason == null)
                  Text(
                    'By check, purchase order or however the host takes it. '
                    "If the host hasn't said how, ask them.",
                    style: small,
                  ),
              ],
            ),
    ),
  );
}

/// A host's "Payments: On / Finish setup / Not set up" card, with setup
/// inside the app (Stripe's form in [PayoutsSetupScreen]). The host's
/// owner sets it up; other managers see the status and who to ask. Shows
/// nothing until the server says online payments are available.
class PayoutsCard extends StatelessWidget {
  const PayoutsCard({
    super.key,
    required this.teamId,
    this.amountCents,
    this.open,
  });

  final String teamId;

  /// The event's fee, for the "payers pay..." line ($100 without one).
  final int? amountCents;

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
            'collecting them yourself. Stall 10 takes the payments and '
            'sends you the whole fee a few days after each event: payers also '
            "pay Stall 10's ${a.feeLabel} and Stripe's card fee. Add your "
            "bank details here; you don't need a Stripe account.",
        'Set up payouts',
      ),
      PayoutStatus.pending => (
        'Finish setting up payments',
        'Stripe needs a few more details before Stall 10 can send you '
            'your fees.',
        'Finish setup',
      ),
      PayoutStatus.ready => (
        'Online payments are on',
        'Teams and players pay their fees in Stall 10, and Stall 10 sends '
            'you the whole fee a few days after each event. $payoutReviewNote '
            'Refund a team from '
            "the event's Teams tab. Payers also pay Stall 10's "
            "${a.feeLabel} and Stripe's card fee.",
        null,
      ),
    };
    final e = vm.earnings;
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
                PayoutsStatusChip(status: a.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(body),
            FeeBreakdownNote(
              amountCents: amountCents ?? 10000,
              currency: 'USD',
              compact: true,
            ),
            if (!e.isEmpty) ...[
              const SizedBox(height: 12),
              Text(
                key: const Key('payout-totals'),
                [
                  'Held ${centsLabel(e.heldCents)}',
                  'Sent ${centsLabel(e.sentCents)}',
                  if (e.refundedCents > 0)
                    'Refunded ${centsLabel(e.refundedCents)}',
                  if (e.disputedCents > 0)
                    'Disputed ${centsLabel(e.disputedCents)}',
                ].join(' · '),
                style: theme.textTheme.bodyMedium,
              ),
              if (e.owedCents > 0)
                Text(
                  '${centsLabel(e.owedCents)} taken back after a refund or '
                  'dispute comes off your next payout.',
                  style: theme.textTheme.bodySmall,
                ),
              if (e.items.isNotEmpty)
                ExpansionTile(
                  key: const Key('payout-items'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: Text(
                    'Each fee (${e.items.length})',
                    style: theme.textTheme.titleSmall,
                  ),
                  children: [
                    for (final i in e.items)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(i.label),
                        subtitle: Text(
                          [
                            i.status.label,
                            if (i.at != null)
                              MaterialLocalizations.of(
                                context,
                              ).formatShortMonthDay(i.at!.toLocal()),
                          ].join(' · '),
                        ),
                        trailing: Text(
                          centsLabel(i.amountCents),
                          style: const TextStyle(
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ],
                ),
            ],
            if (a.status == PayoutStatus.ready && a.canSetUp) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('manage-payouts'),
                onPressed: () async {
                  final payments = _payments(context);
                  if (payments == null) return;
                  await PayoutsSetupScreen.open(
                    context,
                    payments: payments,
                    teamId: teamId,
                    manage: true,
                  );
                  await vm.load.execute();
                },
                child: const Text('Bank account and payouts'),
              ),
            ],
            if (action != null && !a.canSetUp) ...[
              const SizedBox(height: 12),
              Text(
                'Only ${a.ownerName} can set up payments. Ask them to open '
                "the team's settings.",
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (action != null && a.canSetUp) ...[
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('set-up-payments'),
                onPressed: vm.connect.running
                    ? null
                    : () async {
                        // Stripe's form in the app; its own page in the
                        // browser only for tests' fake [open].
                        if (open == null) {
                          final payments = _payments(context);
                          if (payments == null) return;
                          await PayoutsSetupScreen.open(
                            context,
                            payments: payments,
                            teamId: teamId,
                          );
                          await vm.load.execute();
                          return;
                        }
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
        sheet: _sheet(c),
      ),
      builder: (context, vm) => _OnResume(
        load: vm.load.execute,
        child: ListenableBuilder(
          listenable: Listenable.merge([vm, vm.pay]),
          builder: (context, _) {
            final o = vm.options;
            final small = Theme.of(context).textTheme.bodySmall;
            if (vm.checking) {
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text('Checking your payment…', style: small),
                  ],
                ),
              );
            }
            if (vm.returnFailed) {
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Couldn't check your payment. If you paid, it shows "
                        'here once Stripe confirms it.',
                        style: small,
                      ),
                    ),
                    TextButton(
                      onPressed: vm.load.execute,
                      child: const Text('Check again'),
                    ),
                  ],
                ),
              );
            }
            if (o != null && o.processing && !o.paid) {
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  o.reason ??
                      'Your bank payment is processing. It can take up to 4 '
                          'business days.',
                  style: small,
                ),
              );
            }
            final offline = _offline(context, vm);
            if (o == null || !vm.canPay) return offline;
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
                    label: Text(
                      vm.pay.running
                          ? 'Opening checkout…'
                          : 'Pay ${centsLabel(o.chargeCents)} online',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (o.processingCents > 0)
                        'Includes ${centsLabel(o.processingCents)} in '
                            'service and processing fees.',
                      'Secure checkout by Stripe. It shows as paid here once '
                          'Stripe confirms it.',
                      payoutTimingNote,
                      refundPolicyNote,
                    ].join(' '),
                    style: small,
                  ),
                  offline,
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// What payers pay online for [amountCents], which reaches the host in
/// full: the host form's note under the price, and (with [compact]) the
/// payout card's example. Mirrors feeNote in
/// apps/web/components/payments/Payments.tsx.
String? feeNote(
  PaymentFees fees,
  int amountCents,
  String currency, {
  bool compact = false,
}) {
  if (!fees.available || amountCents <= 0) return null;
  final charge = fees.chargeCoveringFees(amountCents);
  final problem = fees.problem(charge, currency);
  if (problem != null) return compact ? null : problem;
  final amount = centsLabel(amountCents);
  if (compact) {
    return 'On a $amount fee, payers pay ${centsLabel(charge)} online and '
        'you get the whole $amount.';
  }
  final ours = centsLabel(fees.platformOn(amountCents));
  final stripe = centsLabel(
    charge - amountCents - fees.platformOn(amountCents),
  );
  return 'Paid online, they pay ${centsLabel(charge)}: $amount, plus '
      "$ours for Stall 10 (${fees.platform.label}) and about $stripe for "
      "Stripe's card fee. You get the whole $amount. Paid your own way, "
      'they pay $amount.';
}

/// [feeNote] for a price a host is setting. Shows nothing while online
/// payments are off.
class FeeBreakdownNote extends StatelessWidget {
  const FeeBreakdownNote({
    super.key,
    required this.amountCents,
    required this.currency,
    this.compact = false,
  });

  final int? amountCents;
  final String currency;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final payments = _payments(context);
    final amount = amountCents;
    if (payments == null || amount == null) return const SizedBox.shrink();
    return ViewModelHost<PaymentFeesViewModel>(
      create: (c) => PaymentFeesViewModel(payments: payments),
      builder: (context, vm) => ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          final note = feeNote(vm.fees, amount, currency, compact: compact);
          if (note == null) return const SizedBox.shrink();
          final theme = Theme.of(context);
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              note,
              key: const Key('fee-breakdown'),
              style: compact
                  ? null
                  : theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
            ),
          );
        },
      ),
    );
  }
}

/// "Paid", "Overdue", "Paying another way" or "Unpaid": a fee's state on the
/// host's lists.
String paymentStatusLabel(EntryPayment? p, {required bool overdue}) {
  if (p?.paid ?? false) return 'Paid';
  if (p?.payingAnotherWay ?? false) return 'Paying another way';
  return overdue ? 'Overdue' : 'Unpaid';
}

/// The host's note on a payment ("Check #1042"): a small button that opens
/// a dialog, returning the new note (null when cancelled).
Future<String?> editPaymentNote(BuildContext context, String note) {
  final controller = TextEditingController(text: note);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Payment note'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: EntryPayment.maxNoteLength,
        decoration: const InputDecoration(
          hintText: 'e.g. Check #1042, PO 55-210, Venmo 3/2',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

/// Shows its builder's answer to "does this server take payments online?",
/// for wording that depends on it (the form's "Other ways to pay").
class PaymentsOnBuilder extends StatelessWidget {
  const PaymentsOnBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, bool on) builder;

  @override
  Widget build(BuildContext context) {
    final payments = _payments(context);
    if (payments == null) return builder(context, false);
    return ViewModelHost<PaymentFeesViewModel>(
      create: (c) => PaymentFeesViewModel(payments: payments),
      builder: (context, vm) => ListenableBuilder(
        listenable: vm,
        builder: (context, _) => builder(context, vm.fees.available),
      ),
    );
  }
}

/// "Payments: On" (green), "Payments: Finish setup" or "Payments: Not set
/// up" (amber: yours to do), for team pages, settings and the event form.
class PayoutsStatusChip extends StatelessWidget {
  const PayoutsStatusChip({super.key, required this.status});

  final PayoutStatus status;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final on = status == PayoutStatus.ready;
    final label = switch (status) {
      PayoutStatus.ready => 'On',
      PayoutStatus.pending => 'Finish setup',
      PayoutStatus.none => 'Not set up',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: on ? c.accentSoft : c.highlightSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Payments: $label',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: on ? c.accentInk : c.highlightInk,
        ),
      ),
    );
  }
}
