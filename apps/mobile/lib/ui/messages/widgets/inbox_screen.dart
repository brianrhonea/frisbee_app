import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/chat/team_chat_activity.dart';
import '../../../data/repositories/draft/message_draft_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../data/repositories/people/people_repository.dart';
import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../../routing/team_chat_links.dart';
import '../../../utils/command.dart';
import '../../chat/widgets/chat_layout.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/app_search_field.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/scoreboard.dart' show SectionHeader;
import '../../core/ui/scroll_to_top.dart';
import '../../core/ui/list_row.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/user_avatar.dart';
import '../../core/ui/view_model_host.dart';
import '../../shell/widgets/app_shell.dart' show ProfileButton;
import '../view_models/direct_chat_viewmodel.dart';
import '../view_models/inbox_viewmodel.dart';
import 'direct_chat_screen.dart';
import '../../moderation/widgets/report_sheet.dart';

/// Width of the inbox list beside an open conversation.
const _listWidth = 300.0;

/// Messages: the user's private conversations. Team chats live on team
/// pages. Wide screens list them on the left and open the picked one on
/// the right; phones list them and slide the picked one in full screen.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key, required this.viewModel});

  final InboxViewModel viewModel;

  void _openFullScreen(BuildContext context, InboxItem item) =>
      context.push(Routes.conversation(item.conversation.id));

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final size = ScreenSize.of(context);
    if (size.isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Chats'),
          actions: [
            IconButton(
              tooltip: 'New message',
              onPressed: () => context.push(Routes.newMessage),
              icon: const Icon(Icons.edit_square),
            ),
            ?ProfileButton.action(context),
            const SizedBox(width: 4),
          ],
        ),
        body: InboxList(
          viewModel: vm,
          onOpen: (item) => _openFullScreen(context, item),
        ),
      );
    }
    final c = AppColors.of(context);
    return Scaffold(
      body: Padding(
        padding: pagePadding(size).copyWith(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Your sideline, connected.',
              subtitle: 'Plan the next point. Keep the conversation going.',
              action: FilledButton.icon(
                onPressed: () => context.push(Routes.newMessage),
                icon: const Icon(Icons.edit_square, size: 18),
                label: const Text('New message'),
              ),
            ),
            Expanded(
              child: Card(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final split =
                        constraints.maxWidth >= chatSplitBreakpoint - 120;
                    return ListenableBuilder(
                      listenable: vm,
                      builder: (context, _) {
                        if (!split) {
                          return InboxList(
                            viewModel: vm,
                            onOpen: (i) => _openFullScreen(context, i),
                          );
                        }
                        final selected = vm.selected;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: constraints.maxWidth >= 900
                                  ? _listWidth
                                  : 260,
                              child: InboxList(
                                viewModel: vm,
                                flat: true,
                                selectedKey: selected?.key,
                                onOpen: vm.select,
                              ),
                            ),
                            VerticalDivider(width: 1, color: c.border),
                            Expanded(
                              child: selected == null
                                  ? const ChatPlaceholder(
                                      text:
                                          'Pick a conversation, or start a '
                                          'new one.',
                                    )
                                  : _Detail(item: selected),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The open conversation, beside the list.
class _Detail extends StatelessWidget {
  const _Detail({required this.item});

  final InboxItem item;

  @override
  Widget build(BuildContext context) => ViewModelHost(
    key: ValueKey('dm-pane-${item.conversation.id}'),
    create: (c) => DirectChatViewModel(
      outbox: c.read(),
      conversationId: item.conversation.id,
      directMessageRepository: c.read(),
      authRepository: c.read(),
      filePicker: c.read(),
      peopleRepository: c.read<PeopleRepository?>(),
      draftRepository: c.read<MessageDraftRepository?>(),
      notificationRepository: c.read<NotificationRepository?>(),
    ),
    builder: (_, dmVm) => DirectChatView(viewModel: dmVm),
  );
}

/// The inbox: a search box, All / Unread / Requests / Archived filters and
/// the entries; [selectedKey] is highlighted. Swipe an entry left to mute
/// or delete it; long-press (or right-click) for those and Archive. The
/// page around it has the one New message button.
class InboxList extends StatefulWidget {
  const InboxList({
    super.key,
    required this.viewModel,
    required this.onOpen,
    this.selectedKey,
    this.flat = false,
  });

  final InboxViewModel viewModel;
  final ValueChanged<InboxItem> onOpen;
  final String? selectedKey;

  /// Rows edge to edge with lines between, for a list that's already in
  /// a panel (beside an open conversation); else grouped in cards.
  final bool flat;

  @override
  State<InboxList> createState() => _InboxListState();
}

class _InboxListState extends State<InboxList> {
  InboxViewModel get viewModel => widget.viewModel;
  final _scroll = ScrollController();

  /// The entry swiped open, if any; opening another closes it.
  final _openSwipe = ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    viewModel.archive.addListener(_onArchive);
    viewModel.delete.addListener(_onDelete);
    viewModel.toggleMute.addListener(_onMute);
  }

  @override
  void dispose() {
    viewModel.archive.removeListener(_onArchive);
    viewModel.delete.removeListener(_onDelete);
    viewModel.toggleMute.removeListener(_onMute);
    _scroll.dispose();
    _openSwipe.dispose();
    super.dispose();
  }

  void _onArchive() => _report(viewModel.archive, 'Done.');

  void _onDelete() => _report(viewModel.delete, 'Conversation deleted.');

  void _onMute() => _report(viewModel.toggleMute, null);

  void _report(Command<Object?> cmd, String? done) {
    if (cmd.error) {
      showErrorSnackBar(context, cmd.result);
    } else if (cmd.completed) {
      if (done != null) showSnackBar(context, done);
    } else {
      return;
    }
    cmd.clearResult();
  }

  Future<void> _confirmDelete(InboxItem item) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete conversation?',
      message:
          'Its messages are removed for you only; ${item.title} still '
          'has them. New messages will bring it back.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) viewModel.delete.execute(item);
  }

  Future<void> _actions(InboxItem item) async {
    final vm = viewModel;
    final action = await showModalBottomSheet<_InboxAction>(
      context: context,
      sheetAnimationStyle: AppMotion.sheetStyle(context),
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!item.isRequest && vm.canMute)
              ListTile(
                leading: Icon(
                  item.muted
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                ),
                title: Text(item.muted ? 'Unmute' : 'Mute'),
                subtitle: item.muted
                    ? null
                    : const Text(
                        'No notifications or unread bubble for this conversation.',
                      ),
                onTap: () => Navigator.pop(context, _InboxAction.mute),
              ),
            if (!item.isRequest)
              ListTile(
                leading: Icon(
                  item.isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
                title: Text(item.isArchived ? 'Unarchive' : 'Archive'),
                onTap: () => Navigator.pop(context, _InboxAction.archive),
              ),
            if (!item.isRequest)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete conversation'),
                subtitle: Text('For you only; ${item.title} keeps it.'),
                onTap: () => Navigator.pop(context, _InboxAction.delete),
              ),
            if (item.isRequest)
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Open the request to accept or delete it.'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case _InboxAction.mute:
        vm.toggleMute.execute(item);
      case _InboxAction.archive:
        vm.archive.execute(item);
      case _InboxAction.delete:
        await _confirmDelete(item);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final vm = viewModel;
      final selectedKey = widget.selectedKey;
      final onOpen = widget.onOpen;
      final c = AppColors.of(context);
      if (!vm.loaded) return const LoadingState();
      // Requests from someone blocked either way aren't shown.
      final blocks = watchBlocks(context);
      final items = [
        for (final i in vm.items)
          if (!(i.isRequest && !i.isGroup && blocks.hides(i.otherId))) i,
      ];
      final allTeamChats = vm.teamChats;
      // Section headings only when both kinds are listed; each folds away
      // (until the app restarts) to keep the other in view.
      final headed = allTeamChats.isNotEmpty && items.isNotEmpty;
      final teamChats = headed && vm.isCollapsed(InboxSection.teams)
          ? const <TeamChatSummary>[]
          : allTeamChats;
      final allItems = items;
      final shownItems = headed && vm.isCollapsed(InboxSection.direct)
          ? const <InboxItem>[]
          : allItems;
      final lead = allTeamChats.isEmpty
          ? 0
          : teamChats.length + (headed ? 1 : 0);
      Widget heading(
        String text,
        InboxSection section,
        int count, {
        bool first = false,
      }) {
        final open = !vm.isCollapsed(section);
        return Padding(
          padding: EdgeInsets.fromLTRB(8, first ? 2 : 14, 8, 0),
          child: InkWell(
            key: Key('inbox-section-${section.name}'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => vm.toggleSection(section),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
              child: Row(
                children: [
                  Expanded(child: SectionHeader(text)),
                  if (!open)
                    Text(
                      '$count',
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: c.muted,
                    semanticLabel: open ? 'Hide $text' : 'Show $text',
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: AppSearchField(
              hint: 'Search messages',
              onChanged: vm.setQuery,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: _FilterBar(
              selected: vm.filter,
              unread: vm.unreadCount,
              unreadTeams: vm.unreadTeamChats,
              unreadDirect: vm.allItems
                  .where((i) => i.unread && !i.muted)
                  .length,
              requests: vm.requestItems
                  .where((i) => i.isGroup || !blocks.hides(i.otherId))
                  .length,
              onSelect: vm.setFilter,
            ),
          ),
          if (vm.filter == InboxFilter.requests)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                "People you don't follow. Open one to read it; they won't "
                "know you've seen it unless you accept.",
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ),
          Expanded(
            child: allItems.isEmpty && allTeamChats.isEmpty
                ? vm.error != null
                      ? ErrorState(error: vm.error)
                      : EmptyState(
                          icon: Icons.chat_bubble_outline,
                          title: switch (vm.filter) {
                            InboxFilter.requests => 'No message requests',
                            InboxFilter.archived => 'Nothing archived',
                            InboxFilter.teams => 'No team chats',
                            InboxFilter.direct => 'No direct messages',
                            _ when vm.allItems.isEmpty => 'No messages yet',
                            _ => 'Nothing here',
                          },
                          message:
                              vm.allItems.isEmpty &&
                                  vm.filter == InboxFilter.all
                              ? 'Message anyone on Stall 10 privately. Tap '
                                    'New message and search by name. Your '
                                    "teams' chats show here too."
                              : null,
                        )
                : ScrollToTop(
                    controller: _scroll,
                    child: ListView.builder(
                      controller: _scroll,
                      padding: EdgeInsets.only(top: headed ? 0 : 4, bottom: 16),
                      itemCount: lead + (headed ? 1 : 0) + shownItems.length,
                      itemBuilder: (context, i) {
                        if (headed && i == 0) {
                          return heading(
                            'Team chats',
                            InboxSection.teams,
                            allTeamChats.length,
                            first: true,
                          );
                        }
                        if (i < lead) {
                          final t = i - (headed ? 1 : 0);
                          final s = teamChats[t];
                          return _TeamChatTile(
                            summary: s,
                            onTap: () {
                              _openSwipe.value = null;
                              final room = s.openRoom;
                              // Over the Chats tab, so the tab bar stays and
                              // back slides: room, chat list, Chats.
                              openTeamChatOverChats(
                                context,
                                s.team.id,
                                roomId: room?.id,
                              );
                            },
                          );
                        }
                        if (headed && i == lead) {
                          return heading(
                            'Direct messages',
                            InboxSection.direct,
                            allItems.length,
                          );
                        }
                        final d = i - lead - (headed ? 1 : 0);
                        final item = shownItems[d];
                        Widget slice(Widget child) => child;
                        final tile = _InboxTile(
                          item: item,
                          selected: item.key == selectedKey,
                          onTap: () {
                            _openSwipe.value = null;
                            onOpen(item);
                          },
                          onActions: () => _actions(item),
                        );
                        if (item.isRequest) return slice(tile);
                        return slice(
                          _SwipeActions(
                            key: ValueKey(item.key),
                            id: item.key,
                            open: _openSwipe,
                            actions: [
                              if (vm.canMute)
                                _SwipeAction(
                                  label: item.muted ? 'Unmute' : 'Mute',
                                  icon: item.muted
                                      ? Icons.notifications_active_outlined
                                      : Icons.notifications_off_outlined,
                                  color: c.field,
                                  foreground: c.ink,
                                  onTap: () => vm.toggleMute.execute(item),
                                ),
                              // Destructive, but in ink rather than red:
                              // red is kept for live games.
                              _SwipeAction(
                                label: 'Delete',
                                icon: Icons.delete_outline,
                                color: c.ink2,
                                foreground: c.card,
                                onTap: () => _confirmDelete(item),
                              ),
                            ],
                            child: tile,
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      );
    },
  );
}

/// All / Teams / Direct / Unread / Requests / Archived as pill chips on
/// one line, scrolling sideways if they don't fit. Teams, Direct and
/// Unread show how many have news (amber: it's the user's to read);
/// Requests' count is turf. Each chip is a 48 px tap target.
class _FilterBar extends StatefulWidget {
  const _FilterBar({
    required this.selected,
    required this.unread,
    required this.unreadTeams,
    required this.unreadDirect,
    required this.requests,
    required this.onSelect,
  });

  final InboxFilter selected;
  final int unread;
  final int unreadTeams;
  final int unreadDirect;
  final int requests;
  final ValueChanged<InboxFilter> onSelect;

  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
  final _scroll = ScrollController();
  final _keys = {for (final f in InboxFilter.values) f: GlobalKey()};
  bool _more = false; // chips hidden past the right edge
  bool _before = false; // and past the left

  InboxFilter get selected => widget.selected;
  int get unread => widget.unread;
  int get unreadTeams => widget.unreadTeams;
  int get unreadDirect => widget.unreadDirect;
  int get requests => widget.requests;
  ValueChanged<InboxFilter> get onSelect => widget.onSelect;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_measure);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measure();
      _reveal();
    });
  }

  @override
  void didUpdateWidget(_FilterBar old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _measure() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final more = p.pixels < p.maxScrollExtent - 1;
    final before = p.pixels > 1;
    if (more != _more || before != _before) {
      setState(() {
        _more = more;
        _before = before;
      });
    }
  }

  /// Scrolls the chosen chip into view.
  void _reveal() {
    final ctx = _keys[selected]?.currentContext;
    if (!mounted || ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: AppMotion.of(context, AppMotion.base),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final filters = [
      (InboxFilter.all, 'All', 0),
      (InboxFilter.teams, 'Teams', unreadTeams),
      (InboxFilter.direct, 'Direct', unreadDirect),
      (InboxFilter.unread, 'Unread', unread),
      (InboxFilter.requests, 'Requests', requests),
      (InboxFilter.archived, 'Archived', 0),
    ];
    final row = SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (filter, label, count) in filters) ...[
            if (filter != InboxFilter.all) const SizedBox(width: AppSpace.sm),
            Semantics(
              key: _keys[filter],
              button: true,
              selected: filter == selected,
              label: count > 0 ? '$label, $count' : label,
              excludeSemantics: true,
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => onSelect(filter),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Center(
                    widthFactor: 1,
                    child: Material(
                      color: filter == selected ? c.chipOn : c.card,
                      shape: StadiumBorder(
                        side: filter == selected
                            ? BorderSide.none
                            : BorderSide(color: c.border2),
                      ),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 36),
                        padding: EdgeInsets.only(
                          left: 14,
                          right: count > 0 ? 8 : 14,
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              maxLines: 1,
                              style: AppText.label.copyWith(
                                color: filter == selected ? c.onChipOn : c.ink,
                              ),
                            ),
                            if (count > 0) ...[
                              const SizedBox(width: 6),
                              if (filter == InboxFilter.requests)
                                Text(
                                  '$count',
                                  style: AppText.label.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: filter == selected
                                        ? c.onChipOn
                                        : c.accent,
                                  ),
                                )
                              else
                                CountPill(count),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
    // A fade on the side with more chips: the cue that the row scrolls.
    if (!_more && !_before) return row;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        colors: [
          _before ? const Color(0x00000000) : const Color(0xFF000000),
          const Color(0xFF000000),
          const Color(0xFF000000),
          _more ? const Color(0x00000000) : const Color(0xFF000000),
        ],
        stops: const [0, 0.08, 0.92, 1],
      ).createShader(rect),
      child: row,
    );
  }
}

class _SwipeAction {
  const _SwipeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color foreground;
  final VoidCallback onTap;
}

class _SwipeActions extends StatefulWidget {
  const _SwipeActions({
    super.key,
    required this.id,
    required this.open,
    required this.actions,
    required this.child,
  });

  final String id;
  final ValueNotifier<String?> open;
  final List<_SwipeAction> actions;
  final Widget child;

  @override
  State<_SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<_SwipeActions>
    with SingleTickerProviderStateMixin {
  static const _buttonWidth = 76.0;

  late final _offset = AnimationController(
    vsync: this,
    duration: AppMotion.base,
  );

  double get _width => _buttonWidth * widget.actions.length;

  @override
  void initState() {
    super.initState();
    widget.open.addListener(_onOpenChanged);
  }

  @override
  void dispose() {
    widget.open.removeListener(_onOpenChanged);
    _offset.dispose();
    super.dispose();
  }

  void _onOpenChanged() {
    if (widget.open.value != widget.id && _offset.value > 0) {
      _offset.animateTo(
        0,
        duration: AppMotion.of(context, AppMotion.base),
        curve: AppMotion.easing,
      );
    }
  }

  void _drag(DragUpdateDetails d) {
    _offset.value = (_offset.value - d.delta.dx / _width).clamp(0.0, 1.0);
  }

  void _settle(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final open = v < -300 || (v <= 300 && _offset.value > 0.5);
    _offset.animateTo(
      open ? 1 : 0,
      duration: AppMotion.of(context, AppMotion.base),
      curve: AppMotion.easing,
    );
    if (open) {
      if (widget.open.value != widget.id) HapticFeedback.selectionClick();
      widget.open.value = widget.id;
    } else if (widget.open.value == widget.id) {
      widget.open.value = null;
    }
  }

  void _close() {
    _offset.animateTo(
      0,
      duration: AppMotion.of(context, AppMotion.base),
      curve: AppMotion.easing,
    );
    if (widget.open.value == widget.id) widget.open.value = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return widget.child;
    return GestureDetector(
      onHorizontalDragUpdate: _drag,
      onHorizontalDragEnd: _settle,
      child: AnimatedBuilder(
        animation: _offset,
        builder: (context, child) {
          final shown = _offset.value * _width;
          return Stack(
            children: [
              if (shown > 0)
                Positioned.fill(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (final a in widget.actions)
                        SizedBox(
                          width: shown / widget.actions.length,
                          child: Material(
                            color: a.color,
                            child: InkWell(
                              onTap: () {
                                _close();
                                a.onTap();
                              },
                              child: ClipRect(
                                child: OverflowBox(
                                  maxWidth: _buttonWidth,
                                  minWidth: _buttonWidth,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(a.icon, color: a.foreground),
                                      const SizedBox(height: 4),
                                      Text(
                                        a.label,
                                        style: TextStyle(
                                          color: a.foreground,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              Transform.translate(offset: Offset(-shown, 0), child: child),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// A team's or community's chat in the inbox: its name, which rooms have
/// new messages, and when the newest was sent.
class _TeamChatTile extends StatelessWidget {
  const _TeamChatTile({required this.summary, required this.onTap});

  final TeamChatSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final unread = summary.unread;
    final when = summary.lastAt;
    return ListRow(
      leading: TeamBadge(
        size: 44,
        community: summary.team.kind == TeamKind.community,
      ),
      title: summary.team.name,
      subtitle: summary.subtitle,
      // "Cam mentioned you: ..." stands out, as Discord's.
      subtitleStyle: summary.mention != null
          ? TextStyle(color: c.accent, fontWeight: FontWeight.w700)
          : null,
      trailing: when == null ? null : _InboxTile.timeText(c, when, unread),
      unread: unread,
      onTap: onTap,
    );
  }
}

class _InboxTile extends StatelessWidget {
  const _InboxTile({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onActions,
  });

  final InboxItem item;
  final bool selected;
  final VoidCallback onTap;

  /// Mute, archive or delete it: long-press, or right-click.
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    // Muted: no unread bubble or bold, as on the Chats tab.
    final unread = item.unread && !item.muted;
    final when = item.lastAt;
    final typing = item.typing;
    return ListRow(
      leading: item.isGroup
          ? _GroupFaces(faces: item.faces)
          : UserAvatar(uid: item.otherId, name: item.title, radius: 22),
      title: item.title,
      subtitle: typing ?? item.preview,
      subtitleStyle: typing == null
          ? null
          : TextStyle(
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
              color: c.accent,
            ),
      trailing: when == null ? null : timeText(c, when, unread),
      unread: unread,
      muted: item.muted,
      selected: selected,
      onTap: onTap,
      onLongPress: onActions,
      onSecondaryTap: onActions,
    );
  }

  /// The time, in amber ink when unread: it's the user's to read.
  static Widget timeText(AppColors c, DateTime d, bool unread) => Text(
    _when(d),
    style: AppText.caption.copyWith(
      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
      color: unread ? c.highlightInk : c.muted,
    ),
  );

  static String _when(DateTime d) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(d, now)) return DateFormat.jm().format(d);
    if (now.difference(d).inDays < 2) return 'Yesterday';
    if (now.difference(d).inDays < 7) return DateFormat.E().format(d);
    return DateFormat.MMMd().format(d);
  }
}

/// A group's photo: two of its members, overlapping, in the space of one.
class _GroupFaces extends StatelessWidget {
  const _GroupFaces({required this.faces});

  final List<({String uid, String name})> faces;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (faces.length < 2) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: c.accentSoft,
        foregroundColor: c.accentInk,
        child: const Icon(Icons.groups, size: 22),
      );
    }
    Widget face(({String uid, String name}) f) => DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c.card, width: 2),
      ),
      child: UserAvatar(uid: f.uid, name: f.name, radius: 15),
    );
    return SizedBox.square(
      dimension: 44,
      child: Stack(
        children: [
          Positioned(top: 0, left: 0, child: face(faces[1])),
          Positioned(bottom: 0, right: 0, child: face(faces[0])),
        ],
      ),
    );
  }
}

enum _InboxAction { mute, archive, delete }
