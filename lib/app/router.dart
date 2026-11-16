import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/logging/diagnostics_service.dart';
import '../domain/models/media_item.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/explore/explore_screen.dart';
import '../features/home/home_screen.dart';
import '../features/music_player/music_screen.dart';
import '../features/settings/diagnostics_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/video_player/video_player_screen.dart';
import '../features/video_player/videos_screen.dart';
import '../shared/widgets/ui_kit.dart';
import 'app_shell.dart';
import '../core/platform_info.dart';

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
                path: '/explore',
                builder: (context, state) => const ExploreScreen(),
              ),
            ],
          ),
          if (PlatformInfo.supportsDownloads)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/downloads',
                  builder: (context, state) => const DownloadsScreen(),
                ),
              ],
            ),
        ],
      ),
      // Settings: opened from the gear in the Home header (own page with a back arrow)
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      // Video player route on ROOT navigator
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/video_player',
        builder: videoPlayerRouteBuilder,
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

/// Builds '/video_player'. The item to play travels in `extra`; when it is
/// missing or not a [MediaItem] (an external deep link, a restored route, a
/// stray push) a small "Nothing to play" page is shown instead of crashing.
///
/// Kept free of side effects: GoRouter runs page builders again on every
/// rebuild (navigation, rotation, theme changes), so the page logs instead.
Widget videoPlayerRouteBuilder(BuildContext context, GoRouterState state) {
  final extra = state.extra;
  return extra is MediaItem
      ? VideoPlayerScreen(item: extra)
      : NothingToPlayScreen(extraType: extra?.runtimeType.toString() ?? 'null');
}

/// Shown when '/video_player' is opened without something to play.
/// "Go back" pops to where the user came from, or goes Home when the route
/// was opened directly (nothing to pop).
class NothingToPlayScreen extends StatefulWidget {
  const NothingToPlayScreen({super.key, required this.extraType});

  /// Type of the `extra` the route got instead of a [MediaItem] ('null' when
  /// there was none); logged to Diagnostics, never its value.
  final String extraType;

  @override
  State<NothingToPlayScreen> createState() => _NothingToPlayScreenState();
}

class _NothingToPlayScreenState extends State<NothingToPlayScreen> {
  @override
  void initState() {
    super.initState();
    // Once per page, and after the frame: logging updates the Diagnostics
    // list, which must not be marked dirty while widgets are being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DiagnosticsService.instance.logEvent('video_player_no_item', {'extra': widget.extraType});
    });
  }

  void _leave(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: EmptyHint(
        icon: Icons.videocam_off_rounded,
        title: 'Nothing to play',
        message: 'This video could not be opened. Pick it again from your library.',
        action: FilledButton.tonal(
          onPressed: () => _leave(context),
          child: const Text('Go back'),
        ),
      ),
    );
  }
}
