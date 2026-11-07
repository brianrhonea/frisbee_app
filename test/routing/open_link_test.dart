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
}
