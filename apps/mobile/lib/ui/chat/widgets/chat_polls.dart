import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/chat.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/scoreboard.dart';
import '../../core/ui/view_model_host.dart';
import '../view_models/chat_poll_viewmodel.dart';
import '../view_models/chat_room_viewmodel.dart';

// Polls posted into team rooms (redesign F33).

/// A poll in a room, as a card: the question, each option with its count
/// and a bar (the viewer's picks in turf), the total, and "Poll closed"
/// once it's over. Tap an option to vote, again to take it back; "See
/// votes" lists who picked what (votes aren't anonymous).
class ChatPollCard extends StatelessWidget {
  const ChatPollCard({super.key, required this.room, required this.message});

  final ChatRoomViewModel room;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) => ViewModelHost(
    key: ValueKey('poll-card-${room.teamId}-${room.roomId}-${message.id}'),
    create: (c) => ChatPollCardViewModel(
      teamId: room.teamId,
      roomId: room.roomId,
      message: message,
      chatRepository: room.chatRepository,
      authRepository: c.read(),
      canManage: () => room.canManagePolls,
      nameOf: room.nameOf,
    ),
    builder: (context, vm) => ListenableBuilder(
      listenable: Listenable.merge([vm, vm.vote, vm.close]),
      builder: (context, _) => _PollCardBody(viewModel: vm),
    ),
  );
}

class _PollCardBody extends StatefulWidget {
  const _PollCardBody({required this.viewModel});

  final ChatPollCardViewModel viewModel;

  @override
  State<_PollCardBody> createState() => _PollCardBodyState();
}

class _PollCardBodyState extends State<_PollCardBody> {
  ChatPollCardViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.vote.addListener(_onCommand);
    vm.close.addListener(_onCommand);
  }

  @override
  void dispose() {
    vm.vote.removeListener(_onCommand);
    vm.close.removeListener(_onCommand);
    super.dispose();
  }

  void _onCommand() {
    for (final c in [vm.vote, vm.close]) {
      if (c.result case Error(:final error)) {
        c.clearResult();
        showErrorSnackBar(context, error);
      }
    }
  }

  Future<void> _confirmClose() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close this poll?'),
        content: const Text('Nobody can vote or change their vote after.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Close poll'),
          ),
        ],
      ),
    );
    if (ok == true) vm.close.execute();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final poll = vm.poll;
    final decoration = BoxDecoration(
      color: c.card,
      border: Border.all(color: c.border),
      borderRadius: BorderRadius.circular(16),
    );
    if (poll == null) {
      return Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(12),
        decoration: decoration,
        child: Text(
          'Poll no longer available',
          style: TextStyle(fontSize: 14, color: c.muted),
        ),
      );
    }
    final counts = vm.counts;
    final total = vm.voterCount;
    final mine = vm.mine;
    final closed = vm.isClosed;
    final status = [
      total == 1 ? '1 vote' : '$total votes',
      if (closed)
        'Poll closed'
      else if (vm.closesAt case final at?)
        'Closes ${DateFormat.MMMEd().add_jm().format(at)}',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.all(12),
      decoration: decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.poll_outlined, size: 18, color: c.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  poll.multiple ? 'POLL · PICK ANY' : 'POLL · PICK ONE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: c.accent,
                  ),
                ),
              ),
              // Amber only for the one thing to do: answer it.
              if (vm.needsVote) const NeedsYouPill('Vote'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            poll.question,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < poll.options.length; i++)
            _PollOption(
              label: poll.options[i],
              count: i < counts.length ? counts[i] : 0,
              total: total,
              chosen: mine.contains(i),
              multiple: poll.multiple,
              onTap: vm.canVote && !vm.vote.running ? () => vm.tap(i) : null,
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  status,
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ),
              if (total > 0)
                TextButton(
                  onPressed: () => _showVoters(context, vm),
                  child: const Text('See votes'),
                ),
              if (vm.canClose)
                TextButton(
                  onPressed: vm.close.running ? null : _confirmClose,
                  child: const Text('Close poll'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PollOption extends StatelessWidget {
  const _PollOption({
    required this.label,
    required this.count,
    required this.total,
    required this.chosen,
    required this.multiple,
    required this.onTap,
  });

  final String label;
  final int count;
  final int total;
  final bool chosen;
  final bool multiple;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final share = total == 0 ? 0.0 : count / total;
    final radius = BorderRadius.circular(12);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        button: onTap != null,
        selected: chosen,
        child: Material(
          color: c.field,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: chosen ? c.accent : Colors.transparent),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: share,
                    child: ColoredBox(color: chosen ? c.accentSoft : c.border),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        chosen
                            ? (multiple
                                  ? Icons.check_box
                                  : Icons.radio_button_checked)
                            : (multiple
                                  ? Icons.check_box_outline_blank
                                  : Icons.radio_button_unchecked),
                        size: 18,
                        color: chosen ? c.accent : c.muted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: chosen
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: chosen ? c.accentInk : c.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: chosen ? c.accentInk : c.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Who picked each option, by name.
Future<void> _showVoters(BuildContext context, ChatPollCardViewModel vm) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final c = AppColors.of(context);
        final poll = vm.poll;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.75,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(
                  poll?.question ?? 'Votes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (poll != null)
                  for (var i = 0; i < poll.options.length; i++) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 2),
                      child: Text(
                        '${poll.options[i]} · ${vm.votersFor(i).length}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                    ),
                    Text(
                      vm.votersFor(i).isEmpty
                          ? 'No votes'
                          : vm.votersFor(i).join(', '),
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                  ],
              ],
            ),
          ),
        );
      },
    );

/// "Poll" in a room's attach menu: the question, 2–6 options, "Allow
/// multiple answers" and an optional closing time, then Post.
Future<void> showCreatePollSheet(BuildContext context, ChatRoomViewModel vm) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => ViewModelHost(
        create: (_) => ChatPollFormViewModel(
          teamId: vm.teamId,
          roomId: vm.roomId,
          chatRepository: vm.chatRepository,
        ),
        builder: (context, form) => CreatePollForm(viewModel: form),
      ),
    );

/// The new-poll form (in [showCreatePollSheet]); closes itself once posted.
class CreatePollForm extends StatefulWidget {
  const CreatePollForm({super.key, required this.viewModel});

  final ChatPollFormViewModel viewModel;

  @override
  State<CreatePollForm> createState() => _CreatePollFormState();
}

class _CreatePollFormState extends State<CreatePollForm> {
  ChatPollFormViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.submit.addListener(_onSubmit);
  }

  @override
  void dispose() {
    vm.submit.removeListener(_onSubmit);
    super.dispose();
  }

  void _onSubmit() {
    switch (vm.submit.result) {
      case Ok():
        vm.submit.clearResult();
        Navigator.of(context).maybePop();
      case Error(:final error):
        vm.submit.clearResult();
        showErrorSnackBar(context, error);
      case null:
    }
  }

  Future<void> _pickClose() async {
    final now = DateTime.now();
    final start = vm.closesAt ?? now.add(const Duration(days: 1));
    final day = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(start),
    );
    if (time == null) return;
    vm.setClosesAt(
      DateTime(day.year, day.month, day.day, time.hour, time.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([vm, vm.submit]),
      builder: (context, _) {
        final problem = vm.problem;
        final closes = vm.closesAt;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'New poll',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('poll-question'),
                    autofocus: true,
                    maxLength: chatPollQuestionMax,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Question',
                      counterText: '',
                    ),
                    onChanged: vm.setQuestion,
                  ),
                  const SizedBox(height: 8),
                  for (final (i, o) in vm.options.indexed)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              key: ValueKey('poll-option-${o.id}'),
                              initialValue: o.text,
                              maxLength: chatPollOptionMax,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                labelText: 'Option ${i + 1}',
                                counterText: '',
                              ),
                              onChanged: (v) => vm.setOption(o.id, v),
                            ),
                          ),
                          if (vm.canRemoveOption)
                            IconButton(
                              tooltip: 'Remove option ${i + 1}',
                              icon: const Icon(Icons.close),
                              onPressed: () => vm.removeOption(o.id),
                            ),
                        ],
                      ),
                    ),
                  if (vm.canAddOption)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: vm.addOption,
                        icon: const Icon(Icons.add),
                        label: const Text('Add option'),
                      ),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Allow multiple answers'),
                    value: vm.multiple,
                    onChanged: vm.setMultiple,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Closes'),
                    subtitle: Text(
                      closes == null
                          ? 'When someone closes it'
                          : DateFormat.MMMEd().add_jm().format(closes),
                    ),
                    onTap: _pickClose,
                    trailing: closes == null
                        ? const Icon(Icons.schedule)
                        : IconButton(
                            tooltip: 'No closing time',
                            icon: const Icon(Icons.close),
                            onPressed: () => vm.setClosesAt(null),
                          ),
                  ),
                  if (problem != null &&
                      vm.question.trim().isNotEmpty &&
                      vm.options.every((o) => o.text.trim().isNotEmpty))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        problem,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: vm.canSubmit ? vm.submit.execute : null,
                    child: Text(vm.submit.running ? 'Posting…' : 'Post poll'),
                  ),
                  Text(
                    'Everyone in the room sees who voted for what.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
