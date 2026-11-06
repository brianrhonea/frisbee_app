import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/routes.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/app_search_field.dart';
import '../../core/ui/brand.dart';
import '../../core/ui/layout.dart';
import '../view_models/web_shell_viewmodel.dart';
import 'join_prompt.dart';
import 'store_badges.dart';
import 'web_footer.dart';

/// A section in the website's navigation.
typedef WebNavLink = ({
  String label,
  String path,
  IconData icon,
  IconData activeIcon,
});

const _home = (
  label: 'Home',
  path: Routes.home,
  icon: Icons.home_outlined,
  activeIcon: Icons.home_rounded,
);
const _community = (
  label: 'Community',
  path: Routes.community,
  icon: Icons.forum_outlined,
  activeIcon: Icons.forum_rounded,
);
const _explore = (
  label: 'Explore',
  path: Routes.explorePath,
  icon: Icons.search,
  activeIcon: Icons.search,
);
const _events = (
  label: 'Events',
  path: Routes.upcomingEvents,
  icon: Icons.event_outlined,
  activeIcon: Icons.event,
);
const _profile = (
  label: 'Profile',
  path: Routes.profile,
  icon: Icons.person_outline_rounded,
  activeIcon: Icons.person_rounded,
);

/// The sections, in order: signed-in people get their Home feed and
/// profile too.
List<WebNavLink> webNavLinks({required bool signedIn}) => signedIn
    ? const [_home, _community, _explore, _events, _profile]
    : const [_community, _explore, _events];

/// Where the website's "Get the app" page lives.
const getTheAppPath = Routes.getTheApp;

/// True when [location] is in [link]'s section.
bool isWebNavLinkActive(WebNavLink link, String location) {
  final path = Uri.parse(location).path;
  return switch (link.path) {
    Routes.explorePath =>
      path == Routes.explorePath ||
          path.startsWith('/players/') ||
          path.startsWith('${Routes.teams}/'),
    _ => path == link.path || path.startsWith('${link.path}/'),
  };
}

/// Widths of the website's three columns, as on x.com.
abstract final class WebLayout {
  /// The page in the middle. App screens inside it get this as their
  /// screen width, so they lay out as on a tablet.
  static const centerWidth = 720.0;
  static const navWidth = 260.0;
  static const railWidth = 88.0;
  static const sideWidth = 340.0;

  /// Below this the site is laid out as on a phone.
  static const phoneWidth = ScreenSize.tabletWidth;

  /// From here the right column shows.
  static const sideFrom = railWidth + centerWidth + sideWidth + 24;

  /// From here the left column has labels.
  static const labelsFrom = navWidth + centerWidth + sideWidth + 24;
}

/// The website's frame, laid out like x.com: navigation on the left, the
/// page in the middle, search, a sign-up (or get the app) card and the
/// footer on the right. Signed-out visitors see a banner asking them to
/// join along the bottom. On phones the navigation moves to a bottom bar.
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final width = MediaQuery.sizeOf(context).width;
      final signedIn = viewModel.user != null;
      final links = webNavLinks(signedIn: signedIn);
      final banner = signedIn ? null : const _JoinBanner();
      if (width < WebLayout.phoneWidth) {
        return _PhoneFrame(
          links: links,
          location: location,
          banner: banner,
          child: child,
        );
      }
      final side = width >= WebLayout.sideFrom;
      final labels = width >= WebLayout.labelsFrom;
      final c = AppColors.of(context);
      return Scaffold(
        body: Column(
          children: [
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NavColumn(
                    viewModel: viewModel,
                    links: links,
                    location: location,
                    labels: labels,
                  ),
                  Flexible(
                    child: Container(
                      constraints: const BoxConstraints(
                        maxWidth: WebLayout.centerWidth,
                      ),
                      decoration: BoxDecoration(
                        border: Border.symmetric(
                          vertical: BorderSide(color: c.border),
                        ),
                      ),
                      child: _AsTablet(child: child),
                    ),
                  ),
                  if (side)
                    SizedBox(
                      width: WebLayout.sideWidth,
                      child: _SideColumn(signedIn: signedIn),
                    ),
                ],
              ),
            ),
            ?banner,
          ],
        ),
      );
    },
  );
}

/// Gives the page in the middle column a tablet's screen width, so app
/// screens (which size themselves by the screen, not their box) lay out
/// for the column rather than the whole window.
class _AsTablet extends StatelessWidget {
  const _AsTablet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final media = MediaQuery.of(context);
      final width = box.maxWidth < WebLayout.phoneWidth
          ? WebLayout.phoneWidth
          : box.maxWidth;
      return MediaQuery(
        data: media.copyWith(size: Size(width, media.size.height)),
        child: child,
      );
    },
  );
}

class _NavColumn extends StatelessWidget {
  const _NavColumn({
    required this.viewModel,
    required this.links,
    required this.location,
    required this.labels,
  });

  final WebShellViewModel viewModel;
  final List<WebNavLink> links;
  final String location;
  final bool labels;

  @override
  Widget build(BuildContext context) {
    final signedIn = viewModel.user != null;
    return SizedBox(
      width: labels ? WebLayout.navWidth : WebLayout.railWidth,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: labels ? 16 : 12),
        child: Column(
          crossAxisAlignment: labels
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 14),
            Semantics(
              link: true,
              label: '$appName home',
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => context.go(links.first.path),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: labels
                      ? const FittedBox(child: AppWordmark(size: 32))
                      : const AppLogo(size: 36),
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final link in links)
              _NavItem(
                link: link,
                active: isWebNavLinkActive(link, location),
                labels: labels,
              ),
            const SizedBox(height: 16),
            if (labels)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: () => context.go(getTheAppPath),
                  icon: const Icon(Icons.phone_iphone),
                  label: const Text(
                    'Get the app',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              )
            else
              IconButton.filled(
                tooltip: 'Get the app',
                onPressed: () => context.go(getTheAppPath),
                icon: const Icon(Icons.phone_iphone),
              ),
            const Spacer(),
            if (signedIn)
              _AccountButton(viewModel: viewModel, labels: labels)
            else if (labels)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => context.go(signInHere(context)),
                  child: const Text('Log in'),
                ),
              )
            else
              IconButton(
                tooltip: 'Log in',
                onPressed: () => context.go(signInHere(context)),
                icon: const Icon(Icons.login),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.link,
    required this.active,
    required this.labels,
  });

  final WebNavLink link;
  final bool active;
  final bool labels;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final icon = Icon(
      active ? link.activeIcon : link.icon,
      size: 27,
      color: c.ink,
    );
    return Tooltip(
      message: labels ? '' : link.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => context.go(link.path),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: labels ? 14 : 12,
            vertical: 12,
          ),
          child: labels
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(width: 18),
                    Flexible(
                      child: Text(
                        link.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 19,
                          color: c.ink,
                          fontWeight: active
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                )
              : Semantics(label: link.label, child: icon),
        ),
      ),
    );
  }
}

class _AccountButton extends StatelessWidget {
  const _AccountButton({required this.viewModel, required this.labels});

  final WebShellViewModel viewModel;
  final bool labels;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final c = AppColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final avatar = PersonAvatar(
      name: vm.userName,
      photoUrl: vm.user?.photoUrl,
      radius: 19,
    );
    return MenuAnchor(
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
        const Divider(height: 1),
        MenuItemButton(
          leadingIcon: const Icon(Icons.logout),
          onPressed: vm.signOut.execute,
          child: Text('Log out ${vm.userName}'),
        ),
      ],
      builder: (context, menu, _) => InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
        child: Tooltip(
          message: labels ? '' : 'Account',
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: labels
                ? Row(
                    children: [
                      avatar,
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          vm.userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(Icons.more_horiz, color: c.muted),
                    ],
                  )
                : avatar,
          ),
        ),
      ),
    );
  }
}

/// Search, then a sign-up card (visitors) or the app downloads (members),
/// then the footer links.
class _SideColumn extends StatelessWidget {
  const _SideColumn({required this.signedIn});

  final bool signedIn;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 12, 16, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          hint: 'Search $appName',
          onSubmitted: (q) => context.go(Routes.explore(query: q)),
        ),
        const SizedBox(height: 16),
        if (signedIn) const _GetTheAppCard() else const _JoinCard(),
        const SizedBox(height: 16),
        const WebFooterLinks(),
      ],
    ),
  );
}

class _SideCard extends StatelessWidget {
  const _SideCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

class _JoinCard extends StatelessWidget {
  const _JoinCard();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return _SideCard(
      title: 'New to $appName?',
      children: [
        Text(
          'Sign up to follow players, join your team and get its schedule, '
          'chats and playbook.',
          style: TextStyle(color: c.muted, fontSize: 13.5),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () => context.go(signUpHere(context)),
          child: const Text('Create account'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => context.go(signInHere(context)),
          child: const Text('Log in'),
        ),
      ],
    );
  }
}

class _GetTheAppCard extends StatelessWidget {
  const _GetTheAppCard();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return _SideCard(
      title: 'Take $appName with you',
      children: [
        Text(
          'Chats, schedules, playbooks, stats and meetings are in the app.',
          style: TextStyle(color: c.muted, fontSize: 13.5),
        ),
        const SizedBox(height: 14),
        const StoreBadges(),
      ],
    );
  }
}

/// x.com's bottom banner for visitors: join, or log in.
class _JoinBanner extends StatelessWidget {
  const _JoinBanner();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final narrow = MediaQuery.sizeOf(context).width < WebLayout.phoneWidth;
    return Material(
      color: c.accent,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Don't miss a point",
                          style: TextStyle(
                            color: c.onAccent,
                            fontSize: narrow ? 16 : 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (!narrow)
                          Text(
                            'People on $appName hear about pickup, tryouts '
                            'and tournaments first.',
                            style: TextStyle(color: c.onAccent),
                          ),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.onAccent,
                      side: BorderSide(color: c.onAccent),
                    ),
                    onPressed: () => context.go(signInHere(context)),
                    child: const Text('Log in'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.onAccent,
                      foregroundColor: c.accent,
                    ),
                    onPressed: () => context.go(signUpHere(context)),
                    child: const Text('Sign up'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Phones: the page full width, a bottom bar of sections, and the join
/// banner above it for visitors. Pages bring their own app bars.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({
    required this.links,
    required this.location,
    required this.banner,
    required this.child,
  });

  final List<WebNavLink> links;
  final String location;
  final Widget? banner;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final selected = links.indexWhere((l) => isWebNavLinkActive(l, location));
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: child),
          ?banner,
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected < 0 ? 0 : selected,
        // Nothing lit when the page isn't one of the sections.
        indicatorColor: selected < 0 ? Colors.transparent : null,
        onDestinationSelected: (i) => context.go(links[i].path),
        destinations: [
          for (final l in links)
            NavigationDestination(
              icon: Icon(l.icon),
              selectedIcon: Icon(l.activeIcon),
              label: l.label,
            ),
        ],
      ),
    );
  }
}
