import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../../routing/open_link.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/status_views.dart';
import '../../payments/widgets/payment_widgets.dart';
import '../view_models/respond_viewmodel.dart';
import 'tournament_parts.dart';

/// The respond flow a step at a time ([RespondViewModel]; the website's
/// /tournaments/:id/respond): Respond (Accept or Decline, or Apply) →
/// Roster (or set later) → Payment (or pay later) → "Request confirmed!".
class RespondScreen extends StatelessWidget {
  const RespondScreen({super.key, required this.viewModel});

  final RespondViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final title = switch (vm.mode) {
          RespondMode.invite => 'Respond to the invite',
          RespondMode.entered => 'Your entry',
          RespondMode.apply => 'Enter a team',
        };
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => _close(context),
            ),
            title: Text(vm.loaded ? title : ''),
          ),
          body: !vm.loaded
              ? const LoadingView()
              : vm.error != null
              ? ErrorView(error: vm.error)
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: _body(context, vm),
                  ),
                ),
        );
      },
    );
  }

  void _close(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      leaveFor(context, Routes.tournament(viewModel.tournamentId));
    }
  }

  Widget _body(BuildContext context, RespondViewModel vm) {
    final c = AppColors.of(context);
    if (vm.blocked case final why?) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(why, style: TextStyle(color: c.ink2, fontSize: 15)),
      );
    }
    return switch (vm.step) {
      RespondStep.declined => _declined(context, vm),
      RespondStep.done => _done(context, vm),
      _ => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _StepBar(vm: vm),
          if (vm.step != RespondStep.respond && vm.deadline != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Roster and payment are due ${_day(vm.deadline!)}.',
                style: TextStyle(fontSize: 12.5, color: c.muted),
              ),
            ),
          const SizedBox(height: 12),
          ...switch (vm.step) {
            RespondStep.respond => _respond(context, vm),
            RespondStep.roster => _roster(context, vm),
            _ => _pay(context, vm),
          },
        ],
      ),
    };
  }

  static String _day(DateTime d) =>
      DateFormat('EEE, MMM d').format(d.toLocal());

  // ---- Step 1: Respond -----------------------------------------------------

  List<Widget> _respond(BuildContext context, RespondViewModel vm) {
    final c = AppColors.of(context);
    final t = vm.tournament!;
    final team = vm.team;
    final fee = vm.owes ? vm.fee : null;
    final members = team == null
        ? const <String>[]
        : ([...team.members.keys]
            ..sort((a, b) => team.nameOf(a).compareTo(team.nameOf(b))));
    Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: c.muted,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: c.ink)),
          ),
        ],
      ),
    );
    final invite = vm.entry;
    return [
      SectionCard(
        title: t.name,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            fact('When', _day(t.startsOn)),
            if (t.location.isNotEmpty) fact('Where', t.location),
            fact('Host', t.hostName),
            if (t.director case final d?) fact('Director', d.name),
            fact('Entry fee', fee == null ? 'Free' : fee.label),
            if (vm.deadline case final d?) fact('Roster and fee due', _day(d)),
            if (vm.mode == RespondMode.invite && invite?.replyBy != null)
              fact('Reply by', _day(invite!.replyBy!)),
          ],
        ),
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Team',
        child: vm.teamFixed
            ? Row(
                children: [
                  TeamMark(name: team?.name ?? '', mine: true, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      team?.name ?? vm.entry?.teamName ?? '',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                  ),
                ],
              )
            : RadioGroup<String>(
                groupValue: vm.teamId,
                onChanged: (id) {
                  if (id != null) vm.selectTeam(id);
                },
                child: Column(
                  children: [
                    for (final x in vm.teamsToEnter)
                      RadioListTile<String>(
                        key: ValueKey('respond-team-${x.id}'),
                        contentPadding: EdgeInsets.zero,
                        value: x.id,
                        title: Text(x.name),
                        subtitle: Text(
                          '${x.members.length} '
                          '${x.members.length == 1 ? 'member' : 'members'}',
                        ),
                      ),
                  ],
                ),
              ),
      ),
      if (vm.mode == RespondMode.apply) ...[
        const SizedBox(height: 12),
        SectionCard(
          title: 'Division',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in vm.divisions)
                ChoiceChip(
                  label: Text(
                    d.isFull ? '${d.label} · full: waitlist' : d.label,
                  ),
                  selected: d.id == vm.divisionId,
                  onSelected: (_) => vm.selectDivision(d.id),
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 12),
      SectionCard(
        title: 'Captains',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Captains report and confirm scores '
              '(up to ${TournamentEntry.maxCaptains}).',
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
            for (final uid in members)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: vm.captains.contains(uid),
                title: Text(
                  team!.nameOf(uid) + (uid == vm.uid ? ' (you)' : ''),
                ),
                onChanged:
                    !vm.captains.contains(uid) &&
                        vm.captains.length >= TournamentEntry.maxCaptains
                    ? null
                    : (v) => vm.toggleCaptain(uid, v == true),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      ListenableBuilder(
        listenable: Listenable.merge([vm.respond, vm.decline]),
        builder: (context, _) {
          final busy = vm.respond.running || vm.decline.running;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                key: const Key('respond-accept'),
                onPressed: busy || !vm.canRespond
                    ? null
                    : () async {
                        await vm.respond.execute();
                        if (context.mounted && vm.respond.error) {
                          showErrorSnackBar(context, vm.respond.result);
                          vm.respond.clearResult();
                        }
                      },
                child: Text(switch (vm.mode) {
                  RespondMode.invite => 'Accept',
                  RespondMode.entered => 'Save and continue',
                  RespondMode.apply => 'Apply',
                }),
              ),
              if (vm.mode == RespondMode.invite) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const Key('respond-decline'),
                  onPressed: busy
                      ? null
                      : () async {
                          if (!await confirmDialog(
                            context,
                            title: 'Decline the invite?',
                            message:
                                "Your team won't play in ${t.name}. The "
                                'organizers will see you declined.',
                            confirmLabel: 'Decline',
                            destructive: true,
                          )) {
                            return;
                          }
                          await vm.decline.execute();
                          if (context.mounted && vm.decline.error) {
                            showErrorSnackBar(context, vm.decline.result);
                            vm.decline.clearResult();
                          }
                        },
                  child: const Text('Decline'),
                ),
              ],
            ],
          );
        },
      ),
    ];
  }

  // ---- Step 2: Roster ------------------------------------------------------

  List<Widget> _roster(BuildContext context, RespondViewModel vm) {
    final c = AppColors.of(context);
    final players = vm.players;
    final min = vm.minRoster;
    return [
      SectionCard(
        title:
            "Who's playing for ${vm.entry?.teamName ?? vm.team?.name ?? 'your team'}?",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              [
                if (min > 0) 'Pick at least $min players from your roster.',
                '${vm.picked.length} picked. You can change it until play '
                    'starts.',
              ].join(' '),
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
            if (players == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (players.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Your roster is empty. Add players to the team, then '
                  'come back.',
                  style: TextStyle(color: c.ink2),
                ),
              )
            else ...[
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: vm.picked.length == players.length,
                title: const Text(
                  'Everyone',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onChanged: vm.locked ? null : (v) => vm.pickEveryone(v == true),
              ),
              for (final p in players)
                CheckboxListTile(
                  key: ValueKey('roster-${p.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: vm.picked.contains(p.id),
                  title: Text(
                    '${p.number != null ? '#${p.number} ' : ''}${p.name}',
                  ),
                  onChanged: vm.locked
                      ? null
                      : (v) => vm.togglePlayer(p.id, v == true),
                ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      ListenableBuilder(
        listenable: vm.saveRoster,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              key: const Key('save-roster'),
              onPressed:
                  vm.saveRoster.running ||
                      vm.locked ||
                      vm.picked.length < (min < 1 ? 1 : min)
                  ? null
                  : () async {
                      await vm.saveRoster.execute();
                      if (context.mounted && vm.saveRoster.error) {
                        showErrorSnackBar(context, vm.saveRoster.result);
                        vm.saveRoster.clearResult();
                      }
                    },
              child: const Text('Save roster'),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('roster-later'),
              onPressed: () => vm.next(RespondStep.roster),
              child: Text(
                vm.deadline == null
                    ? 'Set later'
                    : 'Set later (before the deadline)',
              ),
            ),
          ],
        ),
      ),
    ];
  }

  // ---- Step 3: Payment -----------------------------------------------------

  List<Widget> _pay(BuildContext context, RespondViewModel vm) {
    final c = AppColors.of(context);
    final fee = vm.fee;
    return [
      SectionCard(
        title: 'Entry fee${fee == null ? '' : ' · ${fee.label}'}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              vm.deadline == null
                  ? 'Pay now, or come back and pay later.'
                  : 'Pay now, or come back and pay by ${_day(vm.deadline!)}.',
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
            // The host's own way to pay (or other ways, beside paying online).
            if ((fee?.instructions ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(fee!.instructions, style: TextStyle(color: c.ink2)),
              ),
            if (vm.paid)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Paid.',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: c.positive,
                  ),
                ),
              )
            else
              PayOnlineButton(tournamentId: vm.tournamentId, teamId: vm.teamId),
          ],
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('pay-continue'),
        onPressed: () => vm.next(RespondStep.pay),
        child: const Text('Continue'),
      ),
      const SizedBox(height: 8),
      TextButton(
        key: const Key('pay-later'),
        onPressed: () => vm.next(RespondStep.pay),
        child: Text(
          vm.deadline == null ? 'Pay later' : 'Pay later (before the deadline)',
        ),
      ),
    ];
  }

  // ---- Done ----------------------------------------------------------------

  Widget _done(BuildContext context, RespondViewModel vm) {
    final c = AppColors.of(context);
    final status = vm.status;
    final list = vm.checklist;
    final title = switch (status) {
      EntryStatus.accepted => 'Request confirmed!',
      EntryStatus.waitlisted => "You're on the waitlist",
      _ => 'Request sent!',
    };
    final lead = switch (status) {
      EntryStatus.accepted =>
        '${vm.entry?.teamName ?? 'Your team'} is in ${vm.tournament?.name}.',
      EntryStatus.waitlisted =>
        "The division is full. You'll move up if a spot opens.",
      _ =>
        'The organizers will accept your team or put it on the waitlist. '
            "You'll get a notification.",
    };
    Widget item(String key, bool done, String label, [Widget? action]) =>
        Container(
          key: ValueKey(key),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        Center(
          child: CircleAvatar(
            radius: 30,
            backgroundColor: c.positiveSoft,
            child: Icon(Icons.check, size: 34, color: c.positive),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          key: const Key('respond-done-title'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          lead,
          textAlign: TextAlign.center,
          style: TextStyle(color: c.ink2),
        ),
        const SizedBox(height: 20),
        item('check-status', status == EntryStatus.accepted, switch (status) {
          EntryStatus.accepted => 'Accepted',
          EntryStatus.waitlisted => 'On the waitlist',
          _ => 'Waiting for the organizers',
        }),
        if (!vm.mixed)
          item(
            'check-roster',
            list.rosterSet,
            list.rosterSet ? 'Roster set' : 'Roster to set',
            // It can change until play starts.
            vm.locked
                ? null
                : TextButton(
                    key: const Key('done-roster'),
                    onPressed: () => vm.goTo(RespondStep.roster),
                    child: Text(list.rosterSet ? 'Change' : 'Set roster'),
                  ),
          ),
        if (vm.owes)
          item(
            'check-paid',
            list.paid,
            !vm.paymentKnown
                ? 'Checking payment…'
                : list.paid
                ? 'Paid'
                : 'Fee to pay',
          ),
        // Pay right here: the payment sheet opens straight away (or it
        // says why it can't, with other ways to pay).
        if (vm.owes && vm.paymentKnown && !list.paid)
          Padding(
            key: const Key('done-pay'),
            padding: const EdgeInsets.only(bottom: 8),
            child: PayOnlineButton(
              tournamentId: vm.tournamentId,
              teamId: vm.teamId,
            ),
          ),
        if (!list.complete && vm.deadline != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              "Due ${_day(vm.deadline!)}. You can finish from your team's page.",
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
          ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('respond-go-to-event'),
          onPressed: () =>
              leaveFor(context, Routes.tournament(vm.tournamentId)),
          child: const Text('Go to the event'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _close(context),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _declined(BuildContext context, RespondViewModel vm) {
    final c = AppColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        Text(
          'You declined',
          key: const Key('respond-declined'),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "The organizers can see your team won't be playing. If plans "
          'change, ask them to invite you again.',
          style: TextStyle(color: c.ink2),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => _close(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

/// "Step 2 of 3 · Roster" over a bar of the steps (the event form's).
class _StepBar extends StatelessWidget {
  const _StepBar({required this.vm});

  final RespondViewModel vm;

  static const _titles = {
    RespondStep.respond: 'Respond',
    RespondStep.roster: 'Roster',
    RespondStep.pay: 'Payment',
  };

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final steps = vm.steps;
    final i = steps.indexOf(vm.step);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Step ${i + 1} of ${steps.length} · ${_titles[vm.step]}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: c.ink2,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var x = 0; x < steps.length; x++) ...[
              if (x > 0) const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: x <= i ? c.accent : c.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
