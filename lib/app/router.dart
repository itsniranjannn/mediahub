import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/logging/diagnostics_service.dart';
import '../core/services/download_service_controller.dart';
import '../features/downloads/download_providers.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/home/home_screen.dart';
import '../features/music_player/music_screen.dart';
import '../features/online/online_screen.dart';
import '../features/settings/diagnostics_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/video_player/video_player_screen.dart';
import '../features/video_player/video_queue.dart';
import '../features/video_player/videos_screen.dart';
import '../shared/widgets/ui_kit.dart';
import 'app_shell.dart';
import 'unfocus_on_push.dart';
import '../core/platform_info.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/home',
    // A page, sheet or dialog opening drops a text field's focus, so closing
    // it does not pop the keyboard up again. go_router also hands the root
    // observers to every tab's navigator (StatefulShellRoute's
    // notifyRootObserver, on by default), so this one covers the tabs too.
    observers: [UnfocusOnPush()],
    // The app always starts on Home: a route handed over by the platform
    // (an intent's "route" extra, a deep link) is ignored, so another app
    // cannot open a screen of its choosing on a cold start.
    overridePlatformDefaultLocation: true,
    // A location no route matches goes Home instead of an error page.
    onException: (context, state, router) {
      DiagnosticsService.instance.logEvent('route_not_found', {'path': state.uri.path});
      router.go('/home');
    },
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
                path: '/online',
                builder: (context, state) => const OnlineScreen(),
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
      // The tab used to be "Explore": old links (Home's quick action, saved
      // routes) land on Online.
      GoRoute(
        path: '/explore',
        redirect: (context, state) => '/online',
      ),
      // Settings: opened from the gear in the Home header (own page with a back arrow)
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      // Video player route on ROOT navigator
      videoPlayerRoute(parentNavigatorKey: _rootNavigatorKey),
      // Diagnostics route on ROOT navigator
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/diagnostics',
        builder: (context, state) => const DiagnosticsScreen(),
      ),
    ],
  );

  // The download notification's tap (Android sends 'openDownloads' over the
  // download service channel) opens the Downloads tab.
  if (PlatformInfo.supportsDownloads) {
    final sub = ref.read(downloadServiceControllerProvider).actionEvents.listen((event) {
      if (event == DownloadServiceActions.openDownloads) router.go('/downloads');
    });
    ref.onDispose(sub.cancel);
  }
  return router;
});

/// The '/video_player' route.
///
/// iOS: always a page with no transition, which has no back-swipe. A normal
/// iOS page (a MaterialPage under the theme's Cupertino transition) lays a
/// back-swipe strip along the left edge (20 pt, or the safe-area inset in
/// landscape) over the page, and its drag beats the player's own horizontal
/// seek swipe: a seek that started near the left edge would close the video.
/// go_router 18 happens to build a no-transition page for every `builder`
/// route today (it looks for material_ui's MaterialApp, which this app does
/// not use), so the strip is not there now. This pins it, so a go_router
/// update or a move to material_ui cannot bring it to the player. The
/// player's back arrow closes it, as before.
///
/// Android keeps the `builder`, so its page stays exactly what go_router
/// builds for every other screen.
GoRoute videoPlayerRoute({GlobalKey<NavigatorState>? parentNavigatorKey}) {
  final ios = PlatformInfo.isIOS;
  return GoRoute(
    parentNavigatorKey: parentNavigatorKey,
    path: '/video_player',
    builder: ios ? null : videoPlayerRouteBuilder,
    pageBuilder: ios ? videoPlayerIosPageBuilder : null,
  );
}

/// The iOS page for '/video_player' (see [videoPlayerRoute]): the player from
/// [videoPlayerRouteBuilder] on a page with no transition and no back-swipe.
Page<void> videoPlayerIosPageBuilder(BuildContext context, GoRouterState state) => NoTransitionPage<void>(
      key: state.pageKey,
      name: state.name ?? state.path,
      arguments: <String, String>{...state.pathParameters, ...state.uri.queryParameters},
      restorationId: state.pageKey.value,
      child: Builder(builder: (context) => videoPlayerRouteBuilder(context, state)),
    );

/// Builds '/video_player'. What to play travels in `extra`: a MediaItem
/// (a queue of one) or a [VideoQueue] (the Videos tab's list, for Next and
/// Previous). When it is missing or anything else (an external deep link, a
/// restored route, a stray push) a small "Nothing to play" page is shown
/// instead of crashing.
///
/// Kept free of side effects: GoRouter runs page builders again on every
/// rebuild (navigation, rotation, theme changes), so the page logs instead.
Widget videoPlayerRouteBuilder(BuildContext context, GoRouterState state) {
  final extra = state.extra;
  final queue = VideoQueue.fromExtra(extra);
  return queue != null
      ? VideoPlayerScreen(item: queue.current, queue: queue)
      : NothingToPlayScreen(extraType: extra?.runtimeType.toString() ?? 'null');
}

/// Shown when '/video_player' is opened without something to play.
/// "Go back" pops to where the user came from, or goes Home when the route
/// was opened directly (nothing to pop).
class NothingToPlayScreen extends StatefulWidget {
  const NothingToPlayScreen({super.key, required this.extraType});

  /// Type of the `extra` the route got instead of a MediaItem ('null' when
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
