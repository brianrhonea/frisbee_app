import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/app_search_field.dart';
import '../../core/ui/brand.dart';
import '../../core/ui/layout.dart';
import '../view_models/web_shell_viewmodel.dart';

/// A link in the website's top bar.
typedef WebNavLink = ({String label, String path, IconData icon});

/// The website's sections, in top-bar order.
const List<WebNavLink> webNavLinks = [
  (label: 'Explore', path: Routes.explorePath, icon: Icons.explore_outlined),
  (label: 'Events', path: Routes.tournaments, icon: Icons.event_outlined),
  (label: 'Rankings', path: Routes.rankings, icon: Icons.leaderboard_outlined),
];

/// Where the website's "Get the app" page lives.
const getTheAppPath = '/get-the-app';

/// The website's frame: a sticky top bar (logo, sections, search, get the
/// app, account) over the page. On narrow screens the sections and account
/// move into a drawer.
class WebShell extends StatelessWidget {
  const WebShell({
    super.key,
    required this.viewModel,
    required this.location,
    required this.child,
  });

  final WebShellViewModel viewModel;

  /// The current path, to highlight its section.
  final String location;
  final Widget child;

  static const barHeight = 64.0;

  @override
  Widget build(BuildContext context) {
    final narrow = ScreenSize.of(context).isMobile;
    final c = AppColors.of(context);
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) => Scaffold(
        endDrawer: narrow
            ? _WebDrawer(viewModel: viewModel, location: location)
            : null,
        body: Column(
          children: [
            Material(
              color: c.card,
              child: Container(
                height: barHeight,
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.border)),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: maxPageWidth),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: narrow
                          ? const _NarrowBar()
                          : _WideBar(viewModel: viewModel, location: location),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// True when [location] is in [link]'s section.
bool isWebNavLinkActive(WebNavLink link, String location) {
  final path = Uri.parse(location).path;
  if (link.path == Routes.explorePath) {
    return path == Routes.explorePath || path.startsWith('/players/');
  }
  return path == link.path || path.startsWith('${link.path}/');
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => Semantics(
    link: true,
    label: '$appName home',
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.go(Routes.explore()),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: AppWordmark(size: 30),
      ),
    ),
  );
}

class _WideBar extends StatelessWidget {
  const _WideBar({required this.viewModel, required this.location});

  final WebShellViewModel viewModel;
  final String location;

  @override
  Widget build(BuildContext context) {
    final wide = ScreenSize.of(context) == ScreenSize.desktop;
    return Row(
      children: [
        const _Logo(),
        const SizedBox(width: 24),
        for (final link in webNavLinks)
          _NavButton(link: link, active: isWebNavLinkActive(link, location)),
        const SizedBox(width: 16),
        // Takes what's left, up to its width, at the right.
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 320 : 240),
              child: AppSearchField(
                hint: 'Search $appName',
                onSubmitted: (q) => context.go(Routes.explore(query: q)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        if (wide) ...[
          FilledButton.icon(
            onPressed: () => context.go(getTheAppPath),
            icon: const Icon(Icons.phone_iphone, size: 18),
            label: const Text('Get the app'),
          ),
          const SizedBox(width: 8),
        ],
        _AccountMenu(viewModel: viewModel),
      ],
    );
  }
}

class _NarrowBar extends StatelessWidget {
  const _NarrowBar();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const _Logo(),
      const Spacer(),
      IconButton(
        tooltip: 'Search',
        onPressed: () => context.go(Routes.explore()),
        icon: const Icon(Icons.search),
      ),
      IconButton(
        tooltip: 'Menu',
        onPressed: () => Scaffold.of(context).openEndDrawer(),
        icon: const Icon(Icons.menu),
      ),
    ],
  );
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.link, required this.active});

  final WebNavLink link;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton(
        onPressed: () => context.go(link.path),
        style: TextButton.styleFrom(
          foregroundColor: active ? c.ink : c.muted,
          backgroundColor: active ? c.accentSoft : null,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        child: Text(
          link.label,
          style: TextStyle(
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.viewModel});

  final WebShellViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return MenuAnchor(
      alignmentOffset: const Offset(-140, 8),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.person_outline),
          onPressed: () => context.go(Routes.profile),
          child: const Text('My profile'),
        ),
        MenuItemButton(
          leadingIcon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
          onPressed: () => vm.setDark.execute(!dark),
          child: Text(dark ? 'Light theme' : 'Dark theme'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.phone_iphone),
          onPressed: () => context.go(getTheAppPath),
          child: const Text('Get the app'),
        ),
        const Divider(height: 1),
        MenuItemButton(
          leadingIcon: const Icon(Icons.logout),
          onPressed: vm.signOut.execute,
          child: const Text('Sign out'),
        ),
      ],
      builder: (context, menu, _) => IconButton(
        tooltip: vm.userName.isEmpty ? 'Account' : vm.userName,
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        icon: PersonAvatar(
          name: vm.userName,
          photoUrl: vm.user?.photoUrl,
          radius: 17,
        ),
      ),
    );
  }
}

class _WebDrawer extends StatelessWidget {
  const _WebDrawer({required this.viewModel, required this.location});

  final WebShellViewModel viewModel;
  final String location;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final dark = Theme.of(context).brightness == Brightness.dark;
    void go(String path) {
      Scaffold.of(context).closeEndDrawer();
      context.go(path);
    }

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            ListTile(
              leading: PersonAvatar(
                name: vm.userName,
                photoUrl: vm.user?.photoUrl,
                radius: 18,
              ),
              title: Text(vm.userName),
              subtitle: const Text('My profile'),
              onTap: () => go(Routes.profile),
            ),
            const Divider(),
            for (final link in webNavLinks)
              ListTile(
                leading: Icon(link.icon),
                title: Text(link.label),
                selected: isWebNavLinkActive(link, location),
                onTap: () => go(link.path),
              ),
            ListTile(
              leading: const Icon(Icons.phone_iphone),
              title: const Text('Get the app'),
              onTap: () => go(getTheAppPath),
            ),
            const Divider(),
            ListTile(
              leading: Icon(dark ? Icons.light_mode : Icons.dark_mode),
              title: Text(dark ? 'Light theme' : 'Dark theme'),
              onTap: () => vm.setDark.execute(!dark),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () {
                Scaffold.of(context).closeEndDrawer();
                vm.signOut.execute();
              },
            ),
          ],
        ),
      ),
    );
  }
}
