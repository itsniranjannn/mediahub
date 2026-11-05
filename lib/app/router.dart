import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/models/media_item.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/home/home_screen.dart';
import '../features/music_player/music_screen.dart';
import '../features/settings/diagnostics_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/video_player/video_player_screen.dart';
import '../features/video_player/videos_screen.dart';
import 'app_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/music',
                builder: (context, state) => const MusicScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/videos',
                builder: (context, state) => const VideosScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/downloads',
                builder: (context, state) => const DownloadsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      // Video player route on ROOT navigator
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/video_player',
        builder: (context, state) {
          final item = state.extra as MediaItem;
          return VideoPlayerScreen(item: item);
        },
      ),
      // Diagnostics route on ROOT navigator
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/diagnostics',
        builder: (context, state) => const DiagnosticsScreen(),
      ),
    ],
  );
});
