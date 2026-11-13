import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/team.dart';
import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/app_search_field.dart';
import '../../core/ui/brand.dart';
import '../../core/ui/disc_icon.dart';
import '../../core/ui/key_hint.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/scroll_to_top.dart';
import '../../teams/widgets/team_section_screen.dart';
import '../view_models/shell_viewmodel.dart';
import 'command_palette.dart';
import 'notification_offers.dart';

/// The app's top-level sections, in the order of the router's shell
/// branches. The first five are the tabs (docs/product-spec.md §3); the
/// profile opens from the user's avatar instead.
enum ShellSection {
  community('Home', 'Home', Icons.home_outlined, Icons.home_rounded),
  explore('Explore', 'Explore', Icons.explore_outlined, Icons.explore),
  events('Events', 'Events', Icons.event_outlined, Icons.event),
  team('Teams', 'Teams', Icons.groups_outlined, Icons.groups_rounded),
  messages(
    'Messages',
    'Messages',
    Icons.chat_bubble_outline_rounded,
    Icons.chat_bubble_rounded,
  ),
  profile(
    'My profile',
    'Profile',
    Icons.person_outline_rounded,
    Icons.person_rounded,
  );

  const ShellSection(this.label, this.shortLabel, this.icon, this.activeIcon);

  final String label;

  /// Label in the phone's bottom bar.
  final String shortLabel;
  final IconData icon;
  final IconData activeIcon;

  /// The sections shown as tabs: all but the profile.
  static final tabs = values.where((s) => s != profile).toList();
}

/// The frame around every top-level page: a sidebar on desktops, an icon
/// rail on tablets (both with a top bar of breadcrumbs, search,
/// notifications and the user's avatar), and a bottom bar on phones.
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.viewModel,
    required this.navigationShell,
    required this.location,
  });

  final ShellViewModel viewModel;
  final StatefulNavigationShell navigationShell;

  /// The current path, for the breadcrumbs.
  final String location;

  ShellSection get _section =>
      ShellSection.values[navigationShell.currentIndex];

  /// Opens section [s]. Tapping the one already open goes back to its
  /// first page, and scrolls the page showing to the top.
  void _select(ShellSection s) {
    final again = s.index == navigationShell.currentIndex;
    if (again) ScrollToTop.request();
    navigationShell.goBranch(s.index, initialLocation: again);
  }

  List<PaletteCommand> _commands() => paletteCommands(
    sections: [
      for (final s in ShellSection.values)
        (label: s.label, icon: s.icon, index: s.index),
    ],
    goToSection: (i) => _select(ShellSection.values[i]),
    teams: viewModel.teams,
  );

  @override
  Widget build(BuildContext context) {
    final size = ScreenSize.of(context);
    final c = AppColors.of(context);
    return ChangeNotifierProvider.value(
      value: viewModel,
      child: AppShortcuts(
        commands: _commands,
        onSection: (i) => _select(ShellSection.values[i]),
        child: _frame(size, c),
      ),
    );
  }

  Widget _frame(ScreenSize size, AppColors c) => NotificationOffers(
    viewModel: viewModel,
    child: ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        if (size.isMobile) {
          // On the profile (not a tab) no tab looks selected: the bar needs
          // an index, so tab 0 gets the unselected look.
          final onTab = _section != ShellSection.profile;
          final bar = NavigationBar(
            selectedIndex: onTab ? _section.index : 0,
            onDestinationSelected: (i) => _select(ShellSection.tabs[i]),
            destinations: [
              for (final s in ShellSection.tabs)
                NavigationDestination(
                  icon: _badged(s, Icon(s.icon)),
                  selectedIcon: _badged(s, Icon(onTab ? s.activeIcon : s.icon)),
                  label: s.shortLabel,
                ),
            ],
          );
          return Scaffold(
            body: navigationShell,
            bottomNavigationBar: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.border)),
              ),
              child: onTab ? bar : _unselected(context, bar),
            ),
          );
        }
        return Scaffold(
          body: Row(
            children: [
              if (size == ScreenSize.desktop)
                _Sidebar(
                  viewModel: viewModel,
                  selected: _section,
                  onSelect: _select,
                )
              else
                _Rail(
                  viewModel: viewModel,
                  selected: _section,
                  onSelect: _select,
                ),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(
                      viewModel: viewModel,
                      crumbs: breadcrumbs(location, viewModel.teamName),
                    ),
                    Expanded(child: navigationShell),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  /// [bar] with its selected tab drawn like the others.
  Widget _unselected(BuildContext context, NavigationBar bar) {
    final theme = NavigationBarTheme.of(context);
    final unselected = <WidgetState>{};
    return NavigationBarTheme(
      data: theme.copyWith(
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          theme.labelTextStyle?.resolve(unselected),
        ),
        iconTheme: WidgetStatePropertyAll(theme.iconTheme?.resolve(unselected)),
      ),
      child: bar,
    );
  }

  Widget _badged(ShellSection s, Widget icon) {
    final count = s == ShellSection.messages ? viewModel.unreadMessages : 0;
    return Badge(isLabelVisible: count > 0, label: Text('$count'), child: icon);
  }
}

/// One step of the breadcrumb trail; [path] is where tapping it goes, null
/// for the page you're on.
typedef Crumb = ({String label, String? path});

/// The breadcrumb trail for [path], starting from its section so the way
/// back is one tap, e.g. Explore › Events › Event. Every step but the last
/// links to its page. [teamName] names the user's teams by id.
List<Crumb> breadcrumbs(String path, String? Function(String id) teamName) {
  final uri = Uri.parse(path);
  final parts = [
    ...uri.pathSegments,
    // A team page's tab, e.g. /teams/t1?section=roster.
    if (uri.pathSegments.length == 2 && uri.pathSegments.first == 'teams')
      ?uri.queryParameters['section'],
  ];
  const community = (label: 'Home', path: Routes.home);
  final explore = (label: 'Explore', path: Routes.explorePath);
  const myTeams = (label: 'Teams', path: Routes.teams);
  Crumb here(String label) => (label: label, path: null);

  final trail = switch (parts.firstOrNull) {
    null || 'home' => [community],
    'schedule' => [(label: 'Events', path: Routes.schedule)],
    'explore' => [explore],
    'players' => [explore, here('Player')],
    'rankings' => [explore, here('Rankings')],
    'messages' => [(label: 'Messages', path: Routes.messages)],
    'profile' => [
      (label: 'My profile', path: Routes.profile),
      if (parts.length > 1) here(_capitalize(parts[1])),
    ],
    'teams' => [
      myTeams,
      ...switch (parts.length) {
        1 => <Crumb>[],
        _ when parts[1] == 'new' => [here('New')],
        _ when parts[1] == 'search' => [here('Find a team')],
        _ => [
          (label: teamName(parts[1]) ?? 'Team', path: Routes.team(parts[1])),
          if (parts.length > 2)
            here(
              TeamSection.values
                      .where((s) => s.path == parts[2])
                      .firstOrNull
                      ?.label ??
                  _capitalize(parts[2]),
            ),
        ],
      },
    ],
    _ => [community],
  };
  // The page you're on isn't a link.
  final last = trail.last;
  return [...trail.take(trail.length - 1), here(last.label)];
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

// Desktop sidebar ------------------------------------------------------------

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.viewModel,
    required this.selected,
    required this.onSelect,
  });

  static const width = 232.0;

  final ShellViewModel viewModel;
  final ShellSection selected;
  final ValueChanged<ShellSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    return Container(
      width: width,
      color: c.sidebar,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: () => onSelect(ShellSection.community),
                  child: AppWordmark(size: 30, color: c.onSidebar),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final s in ShellSection.tabs)
                    _SidebarItem(
                      icon: s.icon,
                      label: s.label,
                      selected: s == selected,
                      count: s == ShellSection.messages ? vm.unreadMessages : 0,
                      onTap: () => onSelect(s),
                    ),
                  if (vm.teams.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                      child: Eyebrow('Your club', color: c.onSidebarMuted),
                    ),
                    for (final t in vm.teams.take(5))
                      _ClubItem(
                        team: t,
                        onTap: () => context.go(Routes.team(t.id)),
                      ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: _InviteCard(teams: vm.teams),
            ),
            Divider(height: 1, color: c.onSidebar.withValues(alpha: 0.08)),
            InkWell(
              onTap: () => onSelect(ShellSection.profile),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Row(
                  children: [
                    PersonAvatar(
                      name: vm.userName,
                      photoUrl: vm.user?.photoUrl,
                      radius: 16,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vm.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.onSidebar,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          if (vm.user?.email case final email?)
                            Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.onSidebarMuted,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.count = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final fg = selected ? c.onHighlight : c.onSidebar;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? c.highlight : Colors.transparent,
        borderRadius: BorderRadius.circular(controlRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(controlRadius),
          hoverColor: c.onSidebar.withValues(alpha: 0.06),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 19, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (count > 0) CountPill(count, dark: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClubItem extends StatelessWidget {
  const _ClubItem({required this.team, required this.onTap});

  final Team team;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final count = team.members.length;
    return InkWell(
      borderRadius: BorderRadius.circular(controlRadius),
      hoverColor: c.onSidebar.withValues(alpha: 0.06),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: [
            Icon(
              team.isCommunity
                  ? Icons.diversity_3_outlined
                  : Icons.landscape_outlined,
              size: 17,
              color: c.highlight,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    team.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.onSidebar,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    team.isCommunity
                        ? '$count ${count == 1 ? 'member' : 'members'}'
                        : '${team.division.label} ${team.level.label.toLowerCase()} · '
                              '$count ${count == 1 ? 'player' : 'players'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.onSidebarMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Better together": sends the user to where they can share an invite
/// code.
class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.teams});

  final List<Team> teams;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final team = teams.where((t) => !t.isCommunity).firstOrNull;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.onSidebar.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(controlRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.flag_outlined, size: 18, color: c.highlight),
          const SizedBox(height: 8),
          Text(
            'Better together.',
            style: TextStyle(
              color: c.onSidebar,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Bring your whole sideline. Invite your teammates.',
            style: TextStyle(color: c.onSidebarMuted, fontSize: 11.5),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => context.go(
              team == null ? Routes.teams : TeamSection.members.route(team.id),
            ),
            child: Text(
              'Invite friends ↗',
              style: TextStyle(
                color: c.highlight,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Tablet rail ----------------------------------------------------------------

class _Rail extends StatelessWidget {
  const _Rail({
    required this.viewModel,
    required this.selected,
    required this.onSelect,
  });

  final ShellViewModel viewModel;
  final ShellSection selected;
  final ValueChanged<ShellSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: 68,
      color: c.sidebar,
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: 18),
            InkWell(
              onTap: () => onSelect(ShellSection.community),
              child: const AppLogo(size: 34),
            ),
            const SizedBox(height: 22),
            for (final s in ShellSection.tabs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Tooltip(
                  message: '${s.label}  ·  ${shortcutLabel('${s.index + 1}')}',
                  child: Material(
                    color: s == selected ? c.highlight : Colors.transparent,
                    borderRadius: BorderRadius.circular(controlRadius),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(controlRadius),
                      onTap: () => onSelect(s),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Badge(
                          isLabelVisible:
                              s == ShellSection.messages &&
                              viewModel.unreadMessages > 0,
                          label: Text('${viewModel.unreadMessages}'),
                          offset: const Offset(-4, 4),
                          child: Center(
                            child: Icon(
                              s == selected ? s.activeIcon : s.icon,
                              size: 21,
                              color: s == selected
                                  ? c.onHighlight
                                  : c.onSidebarMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onSelect(ShellSection.profile),
              child: PersonAvatar(
                name: viewModel.userName,
                photoUrl: viewModel.user?.photoUrl,
                radius: 17,
              ),
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}

// Top bar --------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.viewModel, required this.crumbs});

  final ShellViewModel viewModel;
  final List<Crumb> crumbs;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final desktop = ScreenSize.of(context) == ScreenSize.desktop;
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        bottom: false,
        left: false,
        child: Row(
          children: [
            Expanded(child: _Breadcrumbs(crumbs: crumbs)),
            SizedBox(width: desktop ? 300 : 220, child: const SearchField()),
            const SizedBox(width: 8),
            NotificationsButton(count: viewModel.unreadNotifications),
            const SizedBox(width: 6),
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => context.go(Routes.profile),
              child: PersonAvatar(
                name: viewModel.userName,
                photoUrl: viewModel.user?.photoUrl,
                radius: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.crumbs});

  final List<Crumb> crumbs;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      children: [
        for (final (i, crumb) in crumbs.indexed) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.chevron_right, size: 16, color: c.muted),
            ),
          Flexible(
            child: switch (crumb.path) {
              final path? => TextButton(
                onPressed: () => context.go(path),
                style: TextButton.styleFrom(
                  foregroundColor: c.ink,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(
                  crumb.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              null => Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                child: Text(
                  crumb.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    // Alone, it's the section's name; after links, the page.
                    fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w400,
                    color: i == 0 ? c.ink : c.muted,
                  ),
                ),
              ),
            },
          ),
        ],
      ],
    );
  }
}

/// The top bar's search: opens Explore, the app-wide search, with the
/// query.
class SearchField extends StatelessWidget {
  const SearchField({super.key});

  /// The app-wide search: players, teams, groups and events. Explore's
  /// own box says the same.
  static const hint = 'Search Stall 10';

  @override
  Widget build(BuildContext context) => AppSearchField(
    hint: hint,
    onSubmitted: (q) => context.go(Routes.explore(query: q)),
    // The command menu searches too, and is a keystroke away.
    hintTrailing: showsKeyHints(context) ? KeyHint(shortcutLabel('K')) : null,
  );
}

/// The notifications button: a flying disc, with a dot when there are
/// unread notifications.
class NotificationsButton extends StatelessWidget {
  const NotificationsButton({super.key, required this.count, this.color});

  final int count;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Notifications',
    onPressed: () => context.push(Routes.notifications),
    icon: Badge(
      isLabelVisible: count > 0,
      smallSize: 8,
      child: DiscIcon(color: color),
    ),
  );
}

/// The phone's top bar on top-level pages: the wordmark on green, with
/// search (Explore) and notifications.
class MobileTopBar extends StatelessWidget implements PreferredSizeWidget {
  const MobileTopBar({super.key, this.search = true});

  /// Whether to show the search button; off where the page has a search
  /// bar of its own.
  final bool search;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final unread = maybeShellViewModel(context)?.unreadNotifications ?? 0;
    final avatar = ProfileButton.leading(context);
    return AppBar(
      backgroundColor: c.sidebar,
      foregroundColor: c.onSidebar,
      automaticallyImplyLeading: false,
      leading: avatar,
      titleSpacing: avatar == null ? 16 : 0,
      title: InkWell(
        onTap: () => context.go(Routes.home),
        child: AppWordmark(size: 28, color: c.onSidebar),
      ),
      actions: [
        if (search)
          IconButton(
            tooltip: 'Explore',
            onPressed: () => context.go(Routes.explore()),
            icon: Icon(Icons.search, color: c.onSidebar),
          ),
        NotificationsButton(count: unread, color: c.onSidebar),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// The user's avatar at the top left of a tab's first page on phones: it
/// opens their profile and settings, which have no tab of their own.
/// Nothing on larger screens, where the top bar has the avatar, or outside
/// the app frame.
class ProfileButton extends StatelessWidget {
  const ProfileButton({super.key});

  /// [ProfileButton] as an app bar's leading widget, or null where it shows
  /// nothing (so the bar keeps its default back button).
  static Widget? leading(BuildContext context) =>
      ScreenSize.of(context).isMobile && maybeShellViewModel(context) != null
      ? const ProfileButton()
      : null;

  @override
  Widget build(BuildContext context) {
    final vm = maybeShellViewModel(context);
    if (vm == null || !ScreenSize.of(context).isMobile) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: 'My profile',
      onPressed: () => context.go(Routes.profile),
      icon: PersonAvatar(
        name: vm.userName,
        photoUrl: vm.user?.photoUrl,
        radius: 15,
      ),
    );
  }
}

/// The shell's view model when the page is inside the app frame; null in
/// tests that build a page on its own.
ShellViewModel? maybeShellViewModel(BuildContext context) {
  try {
    return context.watch<ShellViewModel>();
  } on ProviderNotFoundException {
    return null;
  }
}
