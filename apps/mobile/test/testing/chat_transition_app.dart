// A small router with the three pages of NAV1's stack (Chats, a team's chat
// list, a room), built with the app's real `chatPage`, for transition tests
// and frame strips.
import 'package:flutter/material.dart';
import 'package:frisbee_app/ui/chat/widgets/chat_layout.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:go_router/go_router.dart';

const chatsKey = ValueKey('chats');
const listKey = ValueKey('list');
const roomKey = ValueKey('room');

Widget _page(String name, Key key, Color color) => Scaffold(
  key: key,
  backgroundColor: color,
  body: Center(child: Text(name, style: const TextStyle(fontSize: 32))),
);

GoRouter chatTransitionRouter() => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => _page('Chats', chatsKey, const Color(0xFFEFEFF2)),
    ),
    GoRoute(
      path: '/list',
      pageBuilder: (context, state) => chatPage(
        context,
        state.pageKey,
        _page('Team chat list', listKey, const Color(0xFFDCE3FF)),
      ),
    ),
    GoRoute(
      path: '/room',
      pageBuilder: (context, state) => chatPage(
        context,
        state.pageKey,
        _page('# General', roomKey, const Color(0xFFFFFFFF)),
      ),
    ),
  ],
);

Widget chatTransitionApp(GoRouter router, {bool reduceMotion = false}) =>
    MaterialApp.router(
      routerConfig: router,
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
    );
