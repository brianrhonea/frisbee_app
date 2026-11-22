import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/routing/open_link.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('following links to chats never stacks up pages to back out of', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Text('Messages'),
          routes: [
            GoRoute(
              path: 'messages/:id',
              builder: (_, s) => Text('Chat ${s.pathParameters['id']}'),
            ),
            GoRoute(path: 'posts/:id', builder: (_, _) => const Text('Post')),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    router.openLink('/messages/a');
    await tester.pumpAndSettle();
    expect(find.text('Chat a'), findsOneWidget);

    // The chat that's already open: nothing happens.
    router.openLink('/messages/a');
    await tester.pumpAndSettle();
    // Another chat: it takes this one's place.
    router.openLink('/messages/b');
    await tester.pumpAndSettle();
    expect(find.text('Chat b'), findsOneWidget);

    // Something else is pushed over it, as before.
    router.openLink('/posts/p');
    await tester.pumpAndSettle();
    expect(find.text('Post'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Chat b'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Messages'), findsOneWidget);
    expect(router.canPop(), isFalse);
  });

  testWidgets('a profile opened from a page over the tabs keeps a way back', (
    tester,
  ) async {
    final root = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: root,
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/people/:uid',
          builder: (_, s) => Text('Person ${s.pathParameters['uid']}'),
        ),
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => shell,
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/explore',
                  builder: (_, _) => const Text('Explore'),
                ),
                GoRoute(
                  path: '/players/:uid',
                  builder: (_, s) => Text('Player ${s.pathParameters['uid']}'),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/profile',
                  builder: (_, _) => const Text('Profile'),
                  routes: [
                    GoRoute(
                      path: 'following',
                      parentNavigatorKey: root,
                      builder: (context, _) => TextButton(
                        onPressed: () => openPage(context, '/players/x'),
                        child: const Text('Following'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/profile/following');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Following'));
    await tester.pumpAndSettle();
    expect(find.text('Person x'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Following'), findsOneWidget);
  });

  testWidgets('links from Notifications: profiles and follow requests come '
      'back to it', (tester) async {
    final root = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: root,
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/people/:uid',
          builder: (_, s) => Text('Person ${s.pathParameters['uid']}'),
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const Text('Notifications'),
          routes: [
            GoRoute(
              path: 'follow-requests',
              builder: (_, _) => const Text('Requests'),
            ),
          ],
        ),
        // Older notices still link to the old place.
        GoRoute(
          path: '/settings/follow-requests',
          redirect: (_, _) => '/notifications/follow-requests',
        ),
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => shell,
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/home', builder: (_, _) => const Text('Home')),
                GoRoute(
                  path: '/players/:uid',
                  builder: (_, s) => Text('Player ${s.pathParameters['uid']}'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/notifications');
    await tester.pumpAndSettle();

    router.openLink('/players/x');
    await tester.pumpAndSettle();
    expect(find.text('Person x'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);

    router.openLink('/settings/follow-requests');
    await tester.pumpAndSettle();
    expect(find.text('Requests'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
  });

  testWidgets('a tapped push opens its page; back goes to where it belongs, '
      'not where the app was left', (tester) async {
    final root = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: root,
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const Text('Notifications'),
        ),
        GoRoute(
          path: '/posts/:id',
          builder: (_, s) => Text('Post ${s.pathParameters['id']}'),
        ),
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => shell,
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/home', builder: (_, _) => const Text('Home')),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/messages',
                  builder: (_, _) => const Text('Chats'),
                  routes: [
                    GoRoute(
                      path: ':id',
                      parentNavigatorKey: root,
                      builder: (_, s) => Text('Chat ${s.pathParameters['id']}'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    // Left on Notifications; a message's push: back goes to Messages.
    router.push('/notifications');
    await tester.pumpAndSettle();
    router.openFromOutside('/messages/a');
    await tester.pumpAndSettle();
    expect(find.text('Chat a'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Chats'), findsOneWidget);

    // A post's push, from a conversation: back goes to Home.
    router.go('/messages/a');
    await tester.pumpAndSettle();
    router.openFromOutside('/posts/p');
    await tester.pumpAndSettle();
    expect(find.text('Post p'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('a notification tapped in the list: back goes to the page it '
      'belongs under, not the list', (tester) async {
    final root = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: root,
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const Text('Notifications'),
        ),
        GoRoute(
          path: '/people/:uid',
          builder: (_, s) => Text('Person ${s.pathParameters['uid']}'),
        ),
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => shell,
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/home', builder: (_, _) => const Text('Home')),
                GoRoute(
                  path: '/players/:uid',
                  builder: (_, s) => Text('Player ${s.pathParameters['uid']}'),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/teams',
                  builder: (_, _) => const Text('Teams'),
                  routes: [
                    GoRoute(
                      path: ':id',
                      builder: (_, s) => Text('Team ${s.pathParameters['id']}'),
                      routes: [
                        GoRoute(
                          path: 'chats/:room',
                          parentNavigatorKey: root,
                          builder: (_, s) =>
                              Text('Room ${s.pathParameters['room']}'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/messages',
                  builder: (_, _) => const Text('Chats'),
                  routes: [
                    GoRoute(
                      path: ':id',
                      parentNavigatorKey: root,
                      builder: (_, s) => Text('Chat ${s.pathParameters['id']}'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    Future<void> fromList(String link, String opened, String back) async {
      router.go('/home');
      router.push('/notifications');
      await tester.pumpAndSettle();
      router.openFromNotifications(link);
      await tester.pumpAndSettle();
      expect(find.text(opened), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text(back), findsOneWidget);
    }

    await fromList('/teams/t/chats/general', 'Room general', 'Team t');
    await fromList('/messages/a', 'Chat a', 'Chats');
    // A person has nothing above them: back to the list.
    await fromList('/players/x', 'Person x', 'Notifications');
  });

  test('pages over the tabs belong under a tab or their team', () {
    expect(pushParent('/posts/p'), '/home');
    expect(pushParent('/team-events/t/e'), '/teams/t?section=events');
    expect(pushParent('/team-meetings/t/m/room'), '/teams/t?section=events');
    expect(pushParent('/my-events/e'), '/schedule');
    // Tournaments are found on Discover.
    expect(pushParent('/tournaments/x'), '/explore');
    expect(pushParent('/group-tournaments/g/x'), '/teams/g');
    expect(pushParent('/messages/a'), isNull);
    expect(pushParent('/teams/t/chats/r'), isNull);
  });
}
