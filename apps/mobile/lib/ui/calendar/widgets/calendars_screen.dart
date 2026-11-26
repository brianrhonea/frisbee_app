import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/models/calendar.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart' show CountPill, PersonAvatar;
import '../../settings/widgets/settings_widgets.dart';
import '../view_models/calendars_viewmodel.dart';
import '../../core/ui/app_segmented_button.dart';

/// Settings → Calendars: invites, the user's calendars, ones shared with
/// them, and the subscription link for Outlook, Apple and Google Calendar.
class CalendarsScreen extends StatefulWidget {
  const CalendarsScreen({super.key, required this.viewModel});

  final CalendarsViewModel viewModel;

  @override
  State<CalendarsScreen> createState() => _CalendarsScreenState();
}

class _CalendarsScreenState extends State<CalendarsScreen> {
  CalendarsViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.change.addListener(_onChange);
  }

  @override
  void dispose() {
    vm.change.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (vm.change.error && mounted) {
      showErrorSnackBar(context, vm.change.result);
      vm.change.clearResult();
    }
  }

  Future<void> _newCalendar() async {
    final made = await showDialog<(String, CalendarColor)>(
      context: context,
      builder: (_) => const _NewCalendarDialog(),
    );
    if (made != null) await vm.create(made.$1, made.$2);
  }

  void _open(CalendarInfo c) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CalendarDetailScreen(viewModel: vm, calendarId: c.id),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([vm, vm.load, vm.change]),
    builder: (context, _) {
      final c = AppColors.of(context);
      if (!vm.enabled) {
        return const SettingsPage(
          title: 'Calendars',
          children: [
            Padding(
              padding: EdgeInsets.all(AppSpace.xl),
              child: Text(
                "Shared calendars aren't available in this version of "
                'the app. Update the app, or use stall10.app.',
              ),
            ),
          ],
        );
      }
      final calendars = vm.calendars;
      return SettingsPage(
        title: 'Calendars',
        children: [
          if (calendars == null)
            vm.load.error
                ? Padding(
                    padding: const EdgeInsets.all(AppSpace.xl),
                    child: Column(
                      children: [
                        const Text("Couldn't load your calendars."),
                        TextButton(
                          onPressed: vm.load.execute,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  )
                : const Padding(
                    padding: EdgeInsets.all(AppSpace.xxl),
                    child: Center(child: CircularProgressIndicator()),
                  )
          else ...[
            if (vm.invites.isNotEmpty) ...[
              const SizedBox(height: 18),
              SettingsHeading(
                'Invites',
                trailing: CountPill(vm.invites.length),
              ),
              for (final i in vm.invites)
                Padding(
                  key: ValueKey('invite-${i.calendarId}'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _InviteCard(
                    invite: i,
                    onAnswer: vm.busy
                        ? null
                        : (accept) => vm.answer(i, accept: accept),
                  ),
                ),
              const SettingsFooter(
                'Nothing is shared with you until you accept.',
              ),
            ],
            SettingsGroup(
              title: 'Your calendars',
              footer:
                  'Invite people to a calendar as Can view (title, time and '
                  'place, never notes) or Can edit (they add and change '
                  'events too).',
              children: [
                for (final cal in vm.mine)
                  ListTile(
                    key: ValueKey('cal-${cal.id}'),
                    leading: _Dot(cal.color),
                    minLeadingWidth: 10,
                    title: Text(cal.name, style: _rowTitle),
                    subtitle: Text(
                      _peopleLine(cal),
                      style: TextStyle(color: c.muted, fontSize: 12),
                    ),
                    trailing: Icon(Icons.chevron_right, color: c.muted),
                    onTap: () => _open(cal),
                  ),
                ListTile(
                  leading: Icon(Icons.add, color: c.accent),
                  minLeadingWidth: 10,
                  title: Text(
                    'New calendar',
                    style: _rowTitle.copyWith(color: c.accent),
                  ),
                  enabled: !vm.busy,
                  onTap: _newCalendar,
                ),
              ],
            ),
            if (vm.shared.isNotEmpty)
              SettingsGroup(
                title: 'Shared with you',
                children: [
                  for (final cal in vm.shared)
                    ListTile(
                      key: ValueKey('shared-${cal.id}'),
                      leading: _Dot(cal.color),
                      minLeadingWidth: 10,
                      title: Text(cal.name, style: _rowTitle),
                      subtitle: Text(
                        '${cal.owner.name} · ${cal.role.label}',
                        style: TextStyle(color: c.muted, fontSize: 12),
                      ),
                      trailing: TextButton(
                        style: TextButton.styleFrom(foregroundColor: c.muted),
                        onPressed: vm.busy
                            ? null
                            : () async {
                                if (await confirmDialog(
                                  context,
                                  title: 'Leave ${cal.name}?',
                                  message:
                                      "You'll need a new invite to see it "
                                      'again.',
                                  confirmLabel: 'Leave',
                                  destructive: true,
                                )) {
                                  await vm.leave(cal);
                                }
                              },
                        child: const Text('Leave'),
                      ),
                    ),
                ],
              ),
            _Subscribe(viewModel: vm),
          ],
        ],
      );
    },
  );

  static const _rowTitle = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);

  static String _peopleLine(CalendarInfo c) {
    final others = c.members.length - 1;
    final invited = c.pending.length;
    return [
      if (others == 0 && invited == 0) 'Only you',
      if (others > 0) others == 1 ? '1 other person' : '$others other people',
      if (invited > 0) '$invited invited',
    ].join(' · ');
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);

  final CalendarColor color;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: color.color, shape: BoxShape.circle),
  );
}

/// An invite to someone's calendar, on amber: it's the user's to answer.
class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.invite, required this.onAnswer});

  final CalendarInvite invite;
  final ValueChanged<bool>? onAnswer;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final i = invite;
    final answer = onAnswer;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.highlightSoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      // Side by side on wide screens, buttons underneath on phones.
      child: LayoutBuilder(
        builder: (context, box) {
          final who = Row(
            children: [
              PersonAvatar(name: i.from.name, photoUrl: i.from.photoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: i.from.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const TextSpan(text: ' invited you to '),
                          TextSpan(
                            text: i.calendarName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      style: TextStyle(fontSize: 14, color: c.ink),
                    ),
                    Text(
                      i.role.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.highlightInk,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final buttons = Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: answer == null ? null : () => answer(true),
                  child: const Text('Accept'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: answer == null ? null : () => answer(false),
                  child: const Text('Decline'),
                ),
              ),
            ],
          );
          if (box.maxWidth >= 520) {
            return Row(
              children: [
                Expanded(child: who),
                const SizedBox(width: 12),
                SizedBox(width: 240, child: buttons),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [who, const SizedBox(height: 12), buttons],
          );
        },
      ),
    );
  }
}

/// The private subscription link: every calendar the user is on, kept in
/// step in their calendar app.
class _Subscribe extends StatelessWidget {
  const _Subscribe({required this.viewModel});

  final CalendarsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final feed = vm.feed;
    final url = feed.url;
    final webcal = feed.webcal;
    final c = AppColors.of(context);
    const footer =
        "Subscribe with a private link and every calendar you're on shows "
        'up there, kept up to date. Calendar apps check the link on their '
        'own schedule: Apple Calendar as often as its Fetch setting, '
        'Outlook every few hours, Google Calendar up to a day. Anyone with '
        'the link can see those events; reset it if it gets out. Each event '
        'also has Add to calendar.';
    if (url == null || webcal == null) {
      return SettingsGroup(
        title: 'Outlook, Apple and Google Calendar',
        footer: footer,
        children: [
          ListTile(
            leading: const SettingsIcon(Icons.link),
            title: const Text('Get a subscription link'),
            enabled: !vm.busy,
            onTap: vm.resetFeed,
          ),
        ],
      );
    }
    final small = TextButton.styleFrom(
      foregroundColor: c.accent,
      textStyle: const TextStyle(
        fontFamily: appFont,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SettingsHeading('Outlook, Apple and Google Calendar'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: c.accentSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.event_available_outlined,
                          size: 20,
                          color: c.accentInk,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Subscription link is on',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: c.ink,
                              ),
                            ),
                            // Not the link itself: it opens your events
                            // to anyone who has it. Copy link is in Subscribe.
                            Text(
                              'Private to you. Subscribe or copy it below.',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: c.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.event_available_outlined, size: 18),
                    label: const Text('Subscribe'),
                    onPressed: () =>
                        showSubscribeSheet(context, url: url, webcal: webcal),
                  ),
                  const SizedBox(height: 10),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          style: small,
                          onPressed: vm.busy
                              ? null
                              : () async {
                                  if (await confirmDialog(
                                    context,
                                    title: 'Make a new link?',
                                    message:
                                        'The old one stops working, so '
                                        'subscribe again with the new one.',
                                    confirmLabel: 'Reset',
                                  )) {
                                    await vm.resetFeed();
                                  }
                                },
                          child: const Text('Reset link'),
                        ),
                      ),
                      Expanded(
                        child: TextButton(
                          style: small.copyWith(
                            foregroundColor: WidgetStatePropertyAll(c.muted),
                          ),
                          onPressed: vm.busy
                              ? null
                              : () async {
                                  if (await confirmDialog(
                                    context,
                                    title: 'Turn the link off?',
                                    message:
                                        'Calendars subscribed to it stop '
                                        'updating.',
                                    confirmLabel: 'Turn off',
                                    destructive: true,
                                  )) {
                                    await vm.stopFeed();
                                  }
                                },
                          child: const Text('Turn off'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SettingsFooter(footer),
        ],
      ),
    );
  }
}

class CalendarColorChoice extends StatelessWidget {
  const CalendarColorChoice({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final CalendarColor value;
  final ValueChanged<CalendarColor>? onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (final c in CalendarColor.values)
        Semantics(
          label: c.label,
          selected: c == value,
          button: true,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onChanged == null ? null : () => onChanged!(c),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: c.color,
                shape: BoxShape.circle,
                border: c == value
                    ? Border.all(
                        color: Theme.of(context).colorScheme.onSurface,
                        width: 3,
                      )
                    : null,
              ),
              child: c == value
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : null,
            ),
          ),
        ),
    ],
  );
}

class _NewCalendarDialog extends StatefulWidget {
  const _NewCalendarDialog();

  @override
  State<_NewCalendarDialog> createState() => _NewCalendarDialogState();
}

class _NewCalendarDialogState extends State<_NewCalendarDialog> {
  final _name = TextEditingController();
  var _color = CalendarColor.blue;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New calendar'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'e.g. Training',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        CalendarColorChoice(
          value: _color,
          onChanged: (c) => setState(() => _color = c),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _name.text.trim().isEmpty
            ? null
            : () => Navigator.of(context).pop((_name.text.trim(), _color)),
        child: const Text('Create'),
      ),
    ],
  );
}

/// One of the user's calendars: its name and color, the people on it and
/// their roles, invites, and inviting more.
class CalendarDetailScreen extends StatefulWidget {
  const CalendarDetailScreen({
    super.key,
    required this.viewModel,
    required this.calendarId,
  });

  final CalendarsViewModel viewModel;
  final String calendarId;

  @override
  State<CalendarDetailScreen> createState() => _CalendarDetailScreenState();
}

class _CalendarDetailScreenState extends State<CalendarDetailScreen> {
  CalendarsViewModel get vm => widget.viewModel;
  final _query = TextEditingController();
  final _name = TextEditingController();
  Timer? _debounce;
  var _role = CalendarRole.view;

  @override
  void initState() {
    super.initState();
    _name.text = vm.calendar(widget.calendarId)?.name ?? '';
    vm.change.addListener(_onChange);
  }

  @override
  void dispose() {
    vm.change.removeListener(_onChange);
    _debounce?.cancel();
    _query.dispose();
    _name.dispose();
    super.dispose();
  }

  void _onChange() {
    if (vm.change.error && mounted) {
      showErrorSnackBar(context, vm.change.result);
      vm.change.clearResult();
    }
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => vm.search.execute(q));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([vm, vm.change]),
    builder: (context, _) {
      final c = AppColors.of(context);
      final cal = vm.calendar(widget.calendarId);
      if (cal == null) {
        return const SettingsPage(
          title: 'Calendar',
          children: [
            Padding(
              padding: EdgeInsets.all(AppSpace.xl),
              child: Text('This calendar was deleted.'),
            ),
          ],
        );
      }
      final busy = vm.busy;
      final others = [
        for (final m in cal.members)
          if (m.role != CalendarRole.owner) m,
      ];
      return SettingsPage(
        title: cal.name,
        children: [
          SettingsGroup(
            title: 'Name and color',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _name,
                        maxLength: 60,
                        enabled: !busy,
                        decoration: const InputDecoration(labelText: 'Name'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed:
                          busy ||
                              _name.text.trim().isEmpty ||
                              _name.text.trim() == cal.name
                          ? null
                          : () => vm.rename(cal, _name.text),
                      child: const Text('Rename'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: CalendarColorChoice(
                  value: cal.color,
                  onChanged: busy ? null : (color) => vm.recolor(cal, color),
                ),
              ),
            ],
          ),
          SettingsGroup(
            title: 'People',
            footer:
                'Can view shows each event\'s title, time and place, not its '
                'notes. Can edit lets them add and change events too.',
            children: [
              if (others.isEmpty && cal.pending.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Text(
                    'Only you. Invite people below.',
                    style: TextStyle(color: c.muted),
                  ),
                ),
              for (final m in others)
                ListTile(
                  key: ValueKey('member-${m.person.uid}'),
                  leading: PersonAvatar(
                    name: m.person.name,
                    photoUrl: m.person.photoUrl,
                  ),
                  title: Text(m.person.name),
                  subtitle: DropdownButton<CalendarRole>(
                    value: m.role,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    onChanged: busy
                        ? null
                        : (r) {
                            if (r != null && r != m.role) {
                              vm.setRole(cal, m.person.uid, r);
                            }
                          },
                    items: [
                      for (final r in CalendarRole.shareable)
                        DropdownMenuItem(value: r, child: Text(r.label)),
                    ],
                  ),
                  trailing: TextButton(
                    onPressed: busy
                        ? null
                        : () => vm.removeMember(cal, m.person.uid),
                    child: const Text('Remove'),
                  ),
                ),
              for (final m in cal.pending)
                ListTile(
                  key: ValueKey('pending-${m.person.uid}'),
                  leading: PersonAvatar(
                    name: m.person.name,
                    photoUrl: m.person.photoUrl,
                  ),
                  title: Text(m.person.name),
                  subtitle: Text(
                    'Invited · ${m.role.label}',
                    style: TextStyle(color: c.muted),
                  ),
                  trailing: TextButton(
                    onPressed: busy
                        ? null
                        : () => vm.cancelInvite(cal, m.person.uid),
                    child: const Text('Cancel'),
                  ),
                ),
            ],
          ),
          if (!vm.isFull(cal))
            SettingsGroup(
              title: 'Invite someone',
              footer: 'They get an invite and see nothing until they accept.',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: AppSegmentedButton<CalendarRole>(
                    segments: [
                      for (final r in CalendarRole.shareable)
                        ButtonSegment(value: r, label: Text(r.label)),
                    ],
                    selected: {_role},
                    onSelectionChanged: (s) => setState(() => _role = s.first),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: TextField(
                    controller: _query,
                    enabled: !busy,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Name or username',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: _onQuery,
                  ),
                ),
                for (final p in vm.resultsFor(cal))
                  ListTile(
                    key: ValueKey('result-${p.uid}'),
                    leading: PersonAvatar(name: p.name, photoUrl: p.photoUrl),
                    title: Text(p.name),
                    subtitle: p.username == null
                        ? null
                        : Text(
                            '@${p.username}',
                            style: TextStyle(color: c.muted),
                          ),
                    trailing: TextButton(
                      onPressed: busy
                          ? null
                          : () {
                              _query.clear();
                              vm.invite(cal, p.uid, _role);
                            },
                      child: const Text('Invite'),
                    ),
                  ),
              ],
            )
          else
            Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Text(
                'A calendar can have up to ${CalendarsViewModel.maxPeople} '
                'people.',
                style: TextStyle(color: c.muted),
              ),
            ),
          if (!cal.isDefault)
            Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: busy
                    ? null
                    : () async {
                        final nav = Navigator.of(context);
                        if (await confirmDialog(
                          context,
                          title: 'Delete ${cal.name}?',
                          message:
                              'All its events are deleted and everyone on it '
                              'loses it.',
                          confirmLabel: 'Delete',
                          destructive: true,
                        )) {
                          await vm.delete(cal);
                          if (nav.mounted) nav.pop();
                        }
                      },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete calendar'),
              ),
            ),
        ],
      );
    },
  );
}

/// The platform the options are for.
SubscribePlatform _platform() => switch (defaultTargetPlatform) {
  TargetPlatform.iOS => SubscribePlatform.ios,
  TargetPlatform.macOS => SubscribePlatform.macos,
  TargetPlatform.android => SubscribePlatform.android,
  _ => SubscribePlatform.other,
};

/// The one "Subscribe" button's choices: the calendar apps that fit this
/// phone (installed ones first, where the phone lets us see them), and Copy
/// link. Each opens its app's own subscribe screen.
Future<void> showSubscribeSheet(
  BuildContext context, {
  required String url,
  required String webcal,
}) async {
  final platform = _platform();
  final installed = <SubscribeTarget>{};
  var webcalApp = true;
  if (platform == SubscribePlatform.android) {
    // AndroidManifest.xml's <queries> lets the app see these.
    final checks = await Future.wait([
      canLaunchUrl(Uri.parse('ms-outlook://'))
          .timeout(const Duration(seconds: 1), onTimeout: () => false)
          .catchError((Object _) => false),
      canLaunchUrl(Uri.parse(webcal))
          .timeout(const Duration(seconds: 1), onTimeout: () => false)
          .catchError((Object _) => false),
    ]);
    if (checks[0]) installed.add(SubscribeTarget.outlook);
    webcalApp = checks[1];
  }
  final options = [
    for (final o in subscribeOptions(
      (url: url, webcal: webcal),
      platform,
      installed: installed,
    ))
      if (o.target != SubscribeTarget.other || webcalApp) o,
  ];
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Subscribe with',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            for (final o in options)
              ListTile(
                leading: Icon(switch (o.target) {
                  SubscribeTarget.apple => Icons.event_available_outlined,
                  SubscribeTarget.google => Icons.calendar_month_outlined,
                  SubscribeTarget.outlook ||
                  SubscribeTarget.outlookWork => Icons.mail_outline,
                  SubscribeTarget.other => Icons.open_in_new,
                }),
                title: Text(
                  installed.contains(o.target)
                      ? '${o.label} · Installed'
                      : o.label,
                ),
                subtitle: Text(o.detail),
                onTap: () {
                  Navigator.pop(sheet);
                  launchUrl(
                    Uri.parse(o.url),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Copy link'),
              subtitle: const Text(
                'For another app: paste it where it asks '
                'to subscribe from a URL.',
              ),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (sheet.mounted) Navigator.pop(sheet);
                if (context.mounted) showSnackBar(context, 'Link copied');
              },
            ),
          ],
        ),
      ),
    ),
  );
}
