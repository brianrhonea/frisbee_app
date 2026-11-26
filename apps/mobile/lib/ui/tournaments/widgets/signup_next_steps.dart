import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../payments/widgets/payment_widgets.dart';
import '../view_models/hosted_tournament_viewmodel.dart';
import '../view_models/player_signups_viewmodel.dart';
import 'tournament_dialogs.dart';

/// Signs the user up (the signup form), then, for a new signup, the next
/// steps (the website's PlayerSignups phases): Payment when there's a fee
/// (pay now or later), then "You're signed up!" with what's left to do.
Future<void> signUpWithNextSteps(
  BuildContext context, {
  required HostedTournamentViewModel event,
  required PlayerSignupsViewModel signups,
}) async {
  final t = event.tournament!;
  final first = !signups.isSignedUp;
  final a = await showPlayerSignupDialog(
    context,
    divisions: event.divisions,
    initial: signups.mine?.status == SignupStatus.withdrawn
        ? null
        : signups.mine,
    fee: t.entryFee,
  );
  if (a == null) return;
  await signups.signUp.execute(a);
  if (!context.mounted) return;
  if (signups.signUp.error) {
    showErrorSnackBar(context, signups.signUp.result);
    signups.signUp.clearResult();
    return;
  }
  if (!first) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => SignupNextSteps(tournament: t, signups: signups),
    ),
  );
}

/// Payment (with a fee) then Done, after signing up.
class SignupNextSteps extends StatefulWidget {
  const SignupNextSteps({
    super.key,
    required this.tournament,
    required this.signups,
  });

  final HostedTournament tournament;
  final PlayerSignupsViewModel signups;

  @override
  State<SignupNextSteps> createState() => _SignupNextStepsState();
}

class _SignupNextStepsState extends State<SignupNextSteps> {
  late bool _paying = _owes && !_paid;

  EntryFee? get _fee => widget.tournament.entryFee;
  bool get _owes => (_fee?.amountCents ?? 0) > 0;
  bool get _paid => widget.signups.isPaid(widget.signups.uid);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = widget.tournament;
    final s = widget.signups;
    final deadline = DateFormat(
      'EEE, MMM d',
    ).format(t.effectiveDeadline.toLocal());
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final paid = _paid;
        final paying = _paying && !paid;
        return Scaffold(
          appBar: AppBar(
            title: Text(paying ? 'Step 2 of 2 · Payment' : 'Signed up'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: paying
                ? [
                    Text(
                      'Entry fee · ${_fee!.label}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pay now, or come back and pay by $deadline.',
                      style: TextStyle(color: c.ink2),
                    ),
                    if (_fee!.instructions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(_fee!.instructions, style: TextStyle(color: c.ink2)),
                    ],
                    const SizedBox(height: 12),
                    PayOnlineButton(tournamentId: t.id),
                    const SizedBox(height: 12),
                    TextButton(
                      key: const Key('signup-pay-later'),
                      onPressed: () => setState(() => _paying = false),
                      child: const Text('Pay later'),
                    ),
                  ]
                : [
                    Center(
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: c.positiveSoft,
                        child: Icon(Icons.check, size: 34, color: c.positive),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "You're signed up!",
                      key: const Key('signup-done-title'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      switch (s.mine?.status) {
                        SignupStatus.accepted => "You're in ${t.name}.",
                        SignupStatus.waitlisted =>
                          "The division is full: you're on the waitlist.",
                        _ => 'The host will confirm your spot.',
                      },
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.ink2),
                    ),
                    const SizedBox(height: 20),
                    _item(c, true, 'Signed up'),
                    if (_owes)
                      _item(
                        c,
                        paid,
                        paid ? 'Paid' : 'Fee to pay',
                        paid
                            ? null
                            : TextButton(
                                onPressed: () => setState(() => _paying = true),
                                child: const Text('Pay now'),
                              ),
                      ),
                    if (_owes && !paid)
                      Text(
                        'Due $deadline.',
                        style: TextStyle(fontSize: 12.5, color: c.muted),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    ),
                  ],
          ),
        );
      },
    );
  }

  Widget _item(AppColors c, bool done, String label, [Widget? action]) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: done ? c.card : c.highlightSoft,
          borderRadius: BorderRadius.circular(controlRadius),
          border: Border.all(color: done ? c.border : c.highlight),
        ),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: done ? c.positive : c.highlightInk,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: done ? c.ink : c.highlightInk,
                ),
              ),
            ),
            ?action,
          ],
        ),
      );
}
