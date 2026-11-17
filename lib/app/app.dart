import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_config.dart';
import 'router.dart';
import 'theme/app_theme.dart';
import 'theme/font_licenses.dart';

class MediaHubApp extends ConsumerStatefulWidget {
  const MediaHubApp({super.key});

  /// One-time app setup that belongs to the look of the app: draw behind the
  /// system bars (edge-to-edge; Android 15 enforces it anyway) and list the
  /// bundled fonts' licences on the licences page. Runs once per process,
  /// however often the app widget is rebuilt or re-created.
  @visibleForTesting
  static void ensureStartup() {
    if (_started) return;
    _started = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge).ignore();
    LicenseRegistry.addLicense(_fontLicenseEntries);
  }

  static bool _started = false;

  static Stream<LicenseEntry> _fontLicenseEntries() async* {
    for (final font in fontLicenses) {
      yield LicenseEntryWithLineBreaks([font.family], font.text);
    }
  }

  @override
  ConsumerState<MediaHubApp> createState() => _MediaHubAppState();
}

class _MediaHubAppState extends ConsumerState<MediaHubApp> {
  @override
  void initState() {
    super.initState();
    MediaHubApp.ensureStartup();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      // Follows the phone, paper by day and ink at night (docs/DESIGN.md
      // 8.2), once every screen reads the palette; ink until then
      // (AppTheme.lightThemeReady).
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: AppTheme.themeMode,
      routerConfig: router,
    );
  }
}
