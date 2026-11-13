import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/disc_icon.dart';
import '../../core/ui/key_hint.dart';
import '../../core/ui/layout.dart' show TeamBadge;
import '../../posts/widgets/post_composer.dart';

/// One thing the command menu can do.
class PaletteCommand {
  const PaletteCommand({
    required this.label,
    required this.icon,
    required this.run,
    this.group = 'Actions',
    this.keywords = '',
    this.shortcut,
    this.team,
    this.art,
  });

  final String label;
  final IconData icon;

  /// Drawn instead of [icon], e.g. the notifications disc.
  final Widget? art;
  final String group;

  /// Other words it's found by, e.g. "settings" for Profile.
  final String keywords;

  /// Its keyboard shortcut, shown on the right, e.g. "Ctrl 1".
  final String? shortcut;

  /// The team it opens, for its badge.
  final Team? team;

  /// Runs with the shell's context, after the menu closes.
  final void Function(BuildContext context) run;

  bool matches(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+'));
    final text = '$label $group $keywords'.toLowerCase();
    return words.every(text.contains);
  }
}

/// Everything the menu lists: the sections, the user's teams, and common
/// actions.
List<PaletteCommand> paletteCommands({
  required List<({String label, IconData icon, int index})> sections,
  required void Function(int index) goToSection,
  required List<Team> teams,
}) => [
  for (final s in sections)
    PaletteCommand(
      label: s.label,
      icon: s.icon,
      group: 'Go to',
      shortcut: shortcutLabel('${s.index + 1}'),
      run: (_) => goToSection(s.index),
    ),
  for (final t in teams)
    PaletteCommand(
      label: t.name,
      icon: Icons.groups_outlined,
      group: t.isCommunity ? 'Your groups' : 'Your teams',
      keywords: 'team group club',
      team: t,
      run: (c) => c.go(Routes.team(t.id)),
    ),
  PaletteCommand(
    label: 'New post',
    icon: Icons.edit_outlined,
    keywords: 'write share compose',
    run: (c) => showPostComposer(c),
  ),
  PaletteCommand(
    label: 'New message',
    icon: Icons.chat_bubble_outline_rounded,
    keywords: 'dm direct chat',
    run: (c) => c.push(Routes.newMessage),
  ),
  PaletteCommand(
    label: 'Record a workout',
    icon: Icons.directions_run,
    keywords: 'run track gps',
    run: (c) => c.push(Routes.recordWorkout),
  ),
  PaletteCommand(
    label: 'Team calendar',
    icon: Icons.calendar_today_outlined,
    keywords: 'schedule events practice',
    run: (c) => c.go(Routes.schedule),
  ),
  PaletteCommand(
    label: 'Notifications',
    icon: Icons.notifications_none_rounded,
    art: const DiscIcon(),
    keywords: 'alerts bell inbox',
    run: (c) => c.push(Routes.notifications),
  ),
  PaletteCommand(
    label: 'Notification settings',
    icon: Icons.tune,
    keywords: 'push mute',
    run: (c) => c.push(Routes.notificationSettings),
  ),
  PaletteCommand(
    label: 'Start a team',
    icon: Icons.add_circle_outline,
    keywords: 'create new',
    run: (c) => c.go(Routes.createTeam),
  ),
  PaletteCommand(
    label: 'Start a pickup group',
    icon: Icons.diversity_3_outlined,
    keywords: 'create new community',
    run: (c) => c.go(Routes.createGroup),
  ),
  PaletteCommand(
    label: 'People you follow',
    icon: Icons.people_outline,
    keywords: 'following',
    run: (c) => c.go(Routes.following),
  ),
];

/// The command menu (Ctrl K / ⌘K): type to find a page, team or action, or
/// search everything. Arrow keys move, Enter runs, Esc closes.
Future<void> showCommandPalette(
  BuildContext context, {
  required List<PaletteCommand> commands,
}) async {
  final picked = await showDialog<PaletteCommand>(
    context: context,
    barrierColor: Colors.black38,
    builder: (_) => CommandPalette(commands: commands),
  );
  if (picked != null && context.mounted) picked.run(context);
}

class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key, required this.commands});

  final List<PaletteCommand> commands;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  var _selected = 0;

  static const _rowHeight = 48.0;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<PaletteCommand> get _results {
    final q = _text.text.trim();
    if (q.isEmpty) return widget.commands;
    return [
      PaletteCommand(
        label: 'Search Stall 10 for “$q”',
        icon: Icons.search,
        group: 'Search',
        run: (c) => c.go(Routes.explore(query: q)),
      ),
      ...widget.commands.where((c) => c.matches(q)),
    ];
  }

  void _move(int by) {
    final count = _results.length;
    if (count == 0) return;
    setState(() => _selected = (_selected + by) % count);
    final top = _selected * _rowHeight;
    final view = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + _rowHeight > _scroll.offset + view) {
      _scroll.jumpTo(top + _rowHeight - view);
    }
  }

  void _run([PaletteCommand? command]) {
    final results = _results;
    final c =
        command ??
        (results.isEmpty
            ? null
            : results[_selected.clamp(0, results.length - 1)]);
    if (c != null) Navigator.pop(context, c);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final results = _results;
    return Align(
      alignment: const Alignment(0, -0.5),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
        child: Material(
          color: c.card,
          elevation: 12,
          clipBehavior: Clip.antiAlias,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(cardRadius + 4),
            side: BorderSide(color: c.border),
          ),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  _move(1),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  _move(-1),
              const SingleActivator(LogicalKeyboardKey.enter): _run,
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: c.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _text,
                          autofocus: true,
                          onChanged: (_) => setState(() => _selected = 0),
                          onSubmitted: (_) => _run(),
                          style: const TextStyle(fontSize: 16),
                          decoration: InputDecoration(
                            hintText: 'Go to, do or search…',
                            hintStyle: TextStyle(color: c.muted),
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ),
                      const KeyHint('Esc'),
                    ],
                  ),
                ),
                Divider(height: 1, color: c.border),
                Flexible(
                  child: results.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Nothing matches',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.muted),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemExtent: _rowHeight,
                          itemCount: results.length,
                          itemBuilder: (context, i) => _Row(
                            command: results[i],
                            selected: i == _selected,
                            onTap: () => _run(results[i]),
                            onHover: () => setState(() => _selected = i),
                          ),
                        ),
                ),
                Divider(height: 1, color: c.border),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(fontSize: 11.5, color: c.muted),
                    child: const Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        KeyHint('↑'),
                        KeyHint('↓'),
                        Text('to move'),
                        SizedBox(width: 8),
                        KeyHint('Enter'),
                        Text('to open'),
                      ],
                    ),
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

class _Row extends StatelessWidget {
  const _Row({
    required this.command,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final PaletteCommand command;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cmd = command;
    return MouseRegion(
      onHover: (_) {
        if (!selected) onHover();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Material(
          color: selected ? c.accentSoft : Colors.transparent,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
          child: InkWell(
            customBorder: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(controlRadius),
            ),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (cmd.team case final team?)
                    TeamBadge(size: 22, community: team.isCommunity)
                  else
                    IconTheme(
                      data: IconThemeData(size: 20, color: c.ink),
                      child: cmd.art ?? Icon(cmd.icon),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      cmd.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: c.ink,
                      ),
                    ),
                  ),
                  Text(
                    cmd.group,
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                  if (cmd.shortcut case final s?) ...[
                    const SizedBox(width: 10),
                    KeyHint(s),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ctrl K (⌘K) opens the command menu and Ctrl 1–5 (⌘1–5) the sections,
/// from anywhere: in a text box, on a page opened over the shell, or with
/// nothing focused. It listens to the keyboard directly rather than
/// through focus, which is lost when pages change.
class AppShortcuts extends StatefulWidget {
  const AppShortcuts({
    super.key,
    required this.commands,
    required this.onSection,
    required this.child,
  });

  final List<PaletteCommand> Function() commands;
  final void Function(int index) onSection;
  final Widget child;

  static const sectionCount = 5;

  @override
  State<AppShortcuts> createState() => _AppShortcutsState();
}

class _AppShortcutsState extends State<AppShortcuts> {
  var _menuOpen = false;

  static final _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
  ];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    final keys = HardwareKeyboard.instance;
    final modifier = usesCommandKey
        ? keys.isMetaPressed
        : keys.isControlPressed;
    if (!modifier || keys.isAltPressed || keys.isShiftPressed) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyK) {
      _openMenu();
      return true;
    }
    final section = _digits.indexOf(key);
    if (section >= 0 && section < AppShortcuts.sectionCount) {
      // From inside the menu too: close it, then go.
      if (_menuOpen) Navigator.of(context, rootNavigator: true).pop();
      // Going to a branch also clears pages opened over the shell.
      widget.onSection(section);
      return true;
    }
    return false;
  }

  Future<void> _openMenu() async {
    if (_menuOpen) return;
    _menuOpen = true;
    try {
      await showCommandPalette(context, commands: widget.commands());
    } finally {
      _menuOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
