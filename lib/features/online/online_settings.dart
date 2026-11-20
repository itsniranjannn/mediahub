import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/diagnostics_service.dart';
import '../../core/platform_info.dart';
import '../../core/storage/settings_store.dart';

/// Keeps YouTube audio playing with the screen off or the app in the
/// background (Settings → Online, the Online ⋮ menu and the watch strip).
class OnlineBackgroundPlayNotifier extends Notifier<bool> {
  static const String prefKey = 'online_background_play';

  @override
  bool build() => SettingsStore.instance.getBool(prefKey, defaultValue: true);

  void set(bool value) {
    if (value == state) return;
    state = value;
    SettingsStore.instance.setBool(prefKey, value);
    DiagnosticsService.instance.logEvent('setting_online_background_play_changed', {'enabled': value});
  }

  void toggle() => set(!state);
}

final onlineBackgroundPlayProvider =
    NotifierProvider<OnlineBackgroundPlayNotifier, bool>(OnlineBackgroundPlayNotifier.new);

/// Enters picture-in-picture by itself when the user leaves the app while a
/// YouTube video plays on screen.
class OnlineAutoPipNotifier extends Notifier<bool> {
  static const String prefKey = 'online_auto_pip';

  @override
  bool build() => SettingsStore.instance.getBool(prefKey, defaultValue: true);

  void set(bool value) {
    if (value == state) return;
    state = value;
    SettingsStore.instance.setBool(prefKey, value);
    DiagnosticsService.instance.logEvent('setting_online_auto_pip_changed', {'enabled': value});
  }

  void toggle() => set(!state);
}

final onlineAutoPipProvider = NotifierProvider<OnlineAutoPipNotifier, bool>(OnlineAutoPipNotifier.new);

/// Blocks YouTube's ads in the Online tab (Settings → Online and the Online
/// ⋮ menu). The page script and the WebView's request rules are fixed when
/// the WebView starts, so the Online tab opens its page again on a change
/// (`online_ad_block.dart`, `youtube_bridge.js` section g).
class OnlineBlockAdsNotifier extends Notifier<bool> {
  static const String prefKey = 'online_block_ads';

  @override
  bool build() => SettingsStore.instance.getBool(prefKey, defaultValue: true);

  void set(bool value) {
    if (value == state) return;
    state = value;
    SettingsStore.instance.setBool(prefKey, value);
    DiagnosticsService.instance.logEvent('setting_online_block_ads_changed', {'enabled': value});
  }

  void toggle() => set(!state);
}

final onlineBlockAdsProvider = NotifierProvider<OnlineBlockAdsNotifier, bool>(OnlineBlockAdsNotifier.new);

/// Settings → Online: the Block ads row.
const String onlineBlockAdsTitle = 'Block ads';
const String onlineBlockAdsSubtitle = 'Skips video ads and hides sponsored posts in the Online tab. '
    "If a video won't play, turn this off.";

/// Settings → Online: the sign-in row. Signing in happens in the Online tab
/// (⋮ → Sign in to YouTube, or YouTube's own Sign in button); Google decides
/// whether it lets an app's web view sign in, so the row says that too.
const String youTubeSignInSettingsTitle = 'YouTube sign-in';
const String youTubeSignInSettingsBody = 'In the Online tab, tap More options, then Sign in to YouTube. '
    'Google may refuse it inside apps for some accounts. The tab works without an account too.';

/// Settings → Online: what "Clear YouTube data" does, under its title.
String clearYouTubeDataSettingsSubtitle() => PlatformInfo.isIOS
    ? "Signs you out and forgets YouTube's cookies, cache and saved site data on this iPhone."
    : "Signs you out and forgets YouTube's cookies, cache and site settings on this phone.";
