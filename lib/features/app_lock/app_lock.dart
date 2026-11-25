// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../app/theme/app_palette.dart';
import '../../core/logging/diagnostics_service.dart';
import '../../core/platform/device_controls.dart';
import '../../core/platform_info.dart';
import '../../core/storage/settings_store.dart';
import '../../shared/widgets/ui_kit.dart';

/// What App lock covers.
enum AppLockScope {
  /// Every screen (the default).
  wholeApp,

  /// Only the Downloads and Online tabs (children can still play music,
  /// downloaded songs and videos included, in Music and Videos).
  downloadsAndOnline;

  static AppLockScope parse(String? raw) =>
      raw == AppLockScope.downloadsAndOnline.name ? AppLockScope.downloadsAndOnline : AppLockScope.wholeApp;
}

/// Settings → App lock.
@immutable
class AppLockSettings {
  const AppLockSettings({
    this.enabled = false,
    this.scope = AppLockScope.wholeApp,
    this.lockAfterMinutes = 1,
  });

  final bool enabled;
  final AppLockScope scope;

  /// Locks again once MediaHub was in the background this long; 0 = at once.
  final int lockAfterMinutes;

  /// The choices Settings offers.
  static const List<int> minuteChoices = [0, 1, 5, 15, 30];

  static const String enabledKey = 'app_lock_enabled';
  static const String scopeKey = 'app_lock_scope';
  static const String minutesKey = 'app_lock_after_minutes';

  static AppLockSettings load(SettingsStore store) {
    final raw = int.tryParse(store.getString(minutesKey) ?? '');
    return AppLockSettings(
      enabled: store.getBool(enabledKey),
      scope: AppLockScope.parse(store.getString(scopeKey)),
      lockAfterMinutes: raw != null && minuteChoices.contains(raw) ? raw : 1,
    );
  }

  AppLockSettings copyWith({bool? enabled, AppLockScope? scope, int? lockAfterMinutes}) => AppLockSettings(
        enabled: enabled ?? this.enabled,
        scope: scope ?? this.scope,
        lockAfterMinutes: lockAfterMinutes ?? this.lockAfterMinutes,
      );

  /// "Immediately", "After 1 minute", "After 15 minutes".
  static String minutesLabel(int minutes) => switch (minutes) {
        0 => 'Immediately',
        1 => 'After 1 minute',
        _ => 'After $minutes minutes',
      };

  /// What stays open with [scope] (Settings shows it under the row).
  static String scopeHint(AppLockScope scope) => switch (scope) {
        AppLockScope.wholeApp => 'Every screen. Music keeps playing.',
        AppLockScope.downloadsAndOnline => 'Downloaded songs and videos still play in Music and Videos.',
      };

  static String scopeLabel(AppLockScope scope) => switch (scope) {
        AppLockScope.wholeApp => 'The whole app',
        AppLockScope.downloadsAndOnline => 'Downloads and Online tabs only',
      };
}

/// The phone's own unlock: fingerprint, face, or the screen-lock PIN /
/// pattern / password as a fallback (local_auth).
abstract class DeviceAuthenticator {
  /// Whether the phone has a screen lock or biometrics MediaHub can use.
  Future<bool> isAvailable();

  /// Shows the phone's prompt. True when the user proved it is them.
  Future<bool> authenticate(String reason);
}

class LocalAuthAuthenticator implements DeviceAuthenticator {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    if (!PlatformInfo.isAndroid && !PlatformInfo.isIOS) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      // biometricOnly false: the phone's PIN works too (and is the only way
      // on a phone without a fingerprint).
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } catch (e) {
      DiagnosticsService.instance.logEvent('app_lock_auth_error', {'type': e.runtimeType.toString()});
      return false;
    }
  }
}

final deviceAuthenticatorProvider = Provider<DeviceAuthenticator>((ref) => LocalAuthAuthenticator());

@immutable
class AppLockState {
  const AppLockState({
    required this.settings,
    required this.locked,
    this.authenticating = false,
    this.turnedOffNoScreenLock = 0,
  });

  final AppLockSettings settings;

  /// Whether the covered screens are hidden behind the lock right now.
  final bool locked;

  /// The phone's prompt is open (lifecycle changes it causes are ignored).
  final bool authenticating;

  /// Bumped each time [AppLockNotifier.unlock] turned the lock off because
  /// the phone no longer has a screen lock (AppLockGate shows a snackbar).
  final int turnedOffNoScreenLock;

  /// Whether the lock hides the tab at [branchIndex] (Downloads = 4,
  /// Online = 3) when the scope is the two tabs.
  bool coversTab(int branchIndex) =>
      locked && settings.scope == AppLockScope.downloadsAndOnline && (branchIndex == 3 || branchIndex == 4);

  bool get coversWholeApp => locked && settings.scope == AppLockScope.wholeApp;

  AppLockState copyWith({AppLockSettings? settings, bool? locked, bool? authenticating, int? turnedOffNoScreenLock}) =>
      AppLockState(
        settings: settings ?? this.settings,
        locked: locked ?? this.locked,
        authenticating: authenticating ?? this.authenticating,
        turnedOffNoScreenLock: turnedOffNoScreenLock ?? this.turnedOffNoScreenLock,
      );
}

/// The lock: on at start when enabled, and again after MediaHub spent
/// [AppLockSettings.lockAfterMinutes] in the background.
///
/// It only hides screens. Playback, the media notification and its buttons,
/// headset buttons, picture-in-picture and downloads all run below the UI
/// and keep working while it is locked (the notification shows only the
/// song or video name the phone's lock screen shows anyway).
class AppLockNotifier extends Notifier<AppLockState> with WidgetsBindingObserver {
  static final Stopwatch _monotonic = Stopwatch()..start();

  /// Monotonic time (a [Stopwatch], never the wall clock: changing the phone's
  /// date or time zone cannot skip the lock). Overridable in tests.
  @visibleForTesting
  static Duration Function() clock = _monotonicNow;

  static Duration _monotonicNow() => _monotonic.elapsed;

  @visibleForTesting
  static void resetClock() => clock = _monotonicNow;

  Duration? _backgroundSince;

  @override
  AppLockState build() {
    final settings = AppLockSettings.load(SettingsStore.instance);
    WidgetsBinding.instance.addObserver(this);
    DeviceControls.inPip.addListener(_onPipChanged);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      DeviceControls.inPip.removeListener(_onPipChanged);
    });
    DeviceControls.setSecure(settings.enabled);
    return AppLockState(settings: settings, locked: settings.enabled);
  }

  @override
  // ignore: avoid_renaming_method_parameters
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) => onLifecycle(lifecycle);

  /// Picture-in-picture counts as away: Android only reports "inactive" for
  /// it, so the timer starts when the window opens and the time is checked
  /// when it is expanded or closed (the lock screen then covers the app).
  void _onPipChanged() {
    final s = state;
    if (!s.settings.enabled || s.authenticating) return;
    if (DeviceControls.inPip.value) {
      _backgroundSince ??= clock();
    } else {
      _checkAway();
    }
  }

  @visibleForTesting
  void onLifecycle(AppLifecycleState lifecycle) {
    final s = state;
    if (!s.settings.enabled || s.authenticating) return;
    switch (lifecycle) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundSince ??= clock();
      case AppLifecycleState.inactive:
        if (DeviceControls.inPip.value) _backgroundSince ??= clock();
      case AppLifecycleState.resumed:
        _checkAway();
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Back from the background or picture-in-picture: locks when it was away
  /// long enough. A negative (impossible) time locks at once.
  void _checkAway() {
    final s = state;
    final since = _backgroundSince;
    _backgroundSince = null;
    if (since == null || s.locked) return;
    final away = clock() - since;
    if (away.isNegative || away >= Duration(minutes: s.settings.lockAfterMinutes)) {
      state = s.copyWith(locked: true);
    }
  }

  /// Pause between the two screen-lock checks in [_definitelyNoScreenLock].
  @visibleForTesting
  static Duration recheckDelay = const Duration(milliseconds: 400);

  /// True only when the phone says twice, a moment apart, that it has no
  /// screen lock. One "no" can be a passing error (local_auth answers false
  /// on any failure, for one while the Activity is not in front), and that
  /// must never switch the lock off.
  Future<bool> _definitelyNoScreenLock(DeviceAuthenticator auth) async {
    if (await auth.isAvailable()) return false;
    // Not in front (started behind the phone's own lock screen): no verdict.
    final life = WidgetsBinding.instance.lifecycleState;
    if (life != null && life != AppLifecycleState.resumed) return false;
    await Future<void>.delayed(recheckDelay);
    return !await auth.isAvailable();
  }

  /// Shows the phone's prompt; unlocks when it says yes. When the phone no
  /// longer has a screen lock (removed in the phone's settings) nobody could
  /// ever unlock: the lock turns itself off and AppLockGate says so.
  Future<bool> unlock() async {
    if (!state.locked || state.authenticating) return !state.locked;
    state = state.copyWith(authenticating: true);
    final auth = ref.read(deviceAuthenticatorProvider);
    var ok = false;
    var noScreenLock = false;
    try {
      if (!await _definitelyNoScreenLock(auth)) {
        ok = await auth.authenticate('Unlock MediaHub');
      } else {
        noScreenLock = true;
      }
    } finally {
      _backgroundSince = null;
      state = state.copyWith(authenticating: false, locked: !ok && !noScreenLock);
    }
    if (noScreenLock) {
      DiagnosticsService.instance.logEvent('app_lock_off_no_screen_lock', {});
      _save(state.settings.copyWith(enabled: false), locked: false);
      state = state.copyWith(turnedOffNoScreenLock: state.turnedOffNoScreenLock + 1);
      return true;
    }
    return ok;
  }

  /// Turning it on asks for the phone's unlock first (so nobody locks
  /// themselves out of a phone without one). Turning it off asks too.
  Future<bool> setEnabled(bool enabled) async {
    final auth = ref.read(deviceAuthenticatorProvider);
    if (enabled && !await auth.isAvailable()) return false;
    state = state.copyWith(authenticating: true);
    bool ok;
    try {
      ok = await auth.authenticate(enabled ? 'Turn on App lock' : 'Turn off App lock');
    } finally {
      state = state.copyWith(authenticating: false);
    }
    if (!ok) return false;
    _backgroundSince = null;
    _save(state.settings.copyWith(enabled: enabled), locked: false);
    return true;
  }

  void setScope(AppLockScope scope) => _save(state.settings.copyWith(scope: scope));

  void setLockAfterMinutes(int minutes) {
    if (!AppLockSettings.minuteChoices.contains(minutes)) return;
    _save(state.settings.copyWith(lockAfterMinutes: minutes));
  }

  void _save(AppLockSettings settings, {bool? locked}) {
    if (settings.enabled != state.settings.enabled) DeviceControls.setSecure(settings.enabled);
    state = state.copyWith(settings: settings, locked: locked);
    final store = SettingsStore.instance;
    store.setBool(AppLockSettings.enabledKey, settings.enabled);
    store.setString(AppLockSettings.scopeKey, settings.scope.name);
    store.setString(AppLockSettings.minutesKey, '${settings.lockAfterMinutes}');
  }
}

final appLockProvider = NotifierProvider<AppLockNotifier, AppLockState>(AppLockNotifier.new);

/// Whether the lock hides the Downloads tab right now (the whole app, or the
/// Downloads and Online tabs): nothing of it may open over the lock screen.
bool lockHidesDownloads(AppLockState s) => s.coversWholeApp || s.coversTab(4);

/// Wraps the whole app (MaterialApp's builder): the lock screen covers every
/// route while [AppLockState.coversWholeApp]. Never in picture-in-picture:
/// the small window keeps showing the video.
class AppLockGate extends ConsumerWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(appLockProvider.select((s) => s.turnedOffNoScreenLock), (_, _) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content: Text('App lock is off: this phone has no screen lock any more. Set one, then turn App lock on again.'),
      ));
    });
    final covered = ref.watch(appLockProvider.select((s) => s.coversWholeApp));
    return ValueListenableBuilder<bool>(
      valueListenable: DeviceControls.inPip,
      builder: (context, inPip, _) => Stack(
        fit: StackFit.expand,
        children: [
          // Kept in the tree, so the Online tab's page, the players and
          // every screen's state live on behind the lock. Hidden from
          // TalkBack / accessibility services while covered: the titles under
          // the lock screen must not be readable through it.
          ExcludeSemantics(excluding: covered && !inPip, child: child),
          if (covered && !inPip) const Positioned.fill(child: LockScreen()),
        ],
      ),
    );
  }
}

/// Covers one tab (Downloads, Online) when the lock is for those tabs only.
class AppLockTabCover extends ConsumerWidget {
  const AppLockTabCover({super.key, required this.branchIndex, required this.child});

  final int branchIndex;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final covered = ref.watch(appLockProvider.select((s) => s.coversTab(branchIndex)));
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(excluding: covered, child: child),
        if (covered) const Positioned.fill(child: LockScreen()),
      ],
    );
  }
}

/// The lock screen: the canvas, a lock glyph and one Unlock button. It asks
/// by itself once when it appears.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(appLockProvider.notifier).unlock();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final authenticating = ref.watch(appLockProvider.select((s) => s.authenticating));
    return Material(
      color: palette.background,
      child: SafeArea(
        child: EmptyHint(
          icon: Icons.lock_rounded,
          kicker: 'App lock',
          title: 'MediaHub is locked',
          message: 'Use your fingerprint, face or phone PIN to open it. Music keeps playing.',
          action: VoltButton(
            label: 'Unlock',
            icon: Icons.lock_open_rounded,
            onPressed: authenticating ? null : () => ref.read(appLockProvider.notifier).unlock(),
          ),
        ),
      ),
    );
  }
}
