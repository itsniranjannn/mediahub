import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/platform_info.dart';
import '../../personal/extractor_backend.dart';
import '../../personal/format_options.dart';
import '../../personal/format_selection_sheet.dart';
import '../../personal/personal_tools_notifier.dart';
import '../../shared/widgets/ui_kit.dart';
import 'download_providers.dart';
import 'downloads_notifier.dart';

/// "Choose a quality, then download" for web links (YouTube, Instagram ...).
/// Used by the Downloads screen, for pasted links and links sent from the
/// Online tab.
class WebLinkDownloadFlow {
  WebLinkDownloadFlow._();

  /// Longest we wait for yt-dlp to describe a link. A slow site, a huge
  /// playlist / channel page or a stuck extractor must never keep the
  /// "Finding available qualities" dialog up forever.
  static const Duration infoTimeout = Duration(seconds: 90);

  /// True when the yt-dlp based downloader exists on this platform and is switched on.
  static bool isAvailable(WidgetRef ref) {
    return PlatformInfo.supportsWebLinkDownloader &&
        kPersonalToolsEnabled &&
        ref.read(personalToolsProvider).isEnabled;
  }

  /// First-use notice. Returns true when the user agreed (now or earlier).
  static Future<bool> confirmNotice(BuildContext context, WidgetRef ref) async {
    if (ref.read(downloadNoticeAgreedProvider)) return true;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Download Notice'),
        content: const Text(
          'Only download files you have the right to save. MediaHub does not support unauthorized or copyright-protected content.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Agree'),
          ),
        ],
      ),
    );
    // `ref` belongs to the calling screen: it must not be used once that
    // screen is gone (Riverpod throws). Nothing gets queued in that case.
    if (!context.mounted) return false;
    if (result == true) {
      ref.read(downloadNoticeAgreedProvider.notifier).agree();
      return true;
    }
    return false;
  }

  /// Android 13+: ask for the notification permission. Returns true if granted.
  static Future<bool> ensureNotificationPermission() async {
    if (!PlatformInfo.isAndroid) return true;
    try {
      final status = await Permission.notification.status;
      if (status.isGranted) return true;
      final req = await Permission.notification.request();
      return req.isGranted;
    } catch (_) {
      return true;
    }
  }

  /// Shown when a quality lookup is too slow: either the native side gave up
  /// (`INFO_TIMEOUT`, after about 85 s) or our own [infoTimeout] fired first.
  /// One constant so the two paths can never drift apart.
  static const String _tooSlowMessage = 'This link is taking too long. Try again later.';

  static String friendlyError(Object? e) {
    if (e is ExtractorException) {
      switch (e.code) {
        case 'HOST_NOT_ALLOWED':
          return 'This website is not supported by the web link downloader.';
        case 'LOGIN_REQUIRED':
          return 'This video needs a login. Only public videos are supported.';
        case 'PRIVATE_CONTENT':
          return 'This video is private and cannot be downloaded.';
        case 'DRM_PROTECTED':
          return 'This content is DRM protected and cannot be downloaded.';
        case 'NOT_FOUND':
          return 'The video was not found. Check the link.';
        case 'NETWORK_ERROR':
          return 'Network problem. Check your connection and try again.';
        case 'PLAYLIST_NOT_SUPPORTED':
          return "Playlists and channels can't be downloaded. Open a single video link instead.";
        case 'LIVE_NOT_SUPPORTED':
          return "Live streams can't be downloaded.";
        case 'INFO_TIMEOUT':
          // Native watchdog stopped a slow or stuck yt-dlp lookup.
          return _tooSlowMessage;
        default:
          return 'Could not read this link. If it keeps failing, update the downloader engine in Settings.';
      }
    }
    // The quality lookup gave up after [infoTimeout].
    if (e is TimeoutException) return _tooSlowMessage;
    if (e is UnsupportedError) return 'The web link downloader is only available on Android.';
    return 'Could not read this link. Please try again.';
  }

  /// True when a lookup failed because the yt-dlp engine itself could not run
  /// or could not read the site any more (not because of the link: private,
  /// live, playlist, offline ...). For a YouTube link the caller can then try
  /// the downloader that needs no yt-dlp.
  static bool isEngineUnavailable(Object? e) {
    if (e is UnsupportedError || e is MissingPluginException) return true;
    if (e is ExtractorException) {
      return const {'INIT_FAILED', 'FEATURE_DISABLED', 'EXTRACTION_FAILED', 'EMPTY_METADATA'}.contains(e.code);
    }
    return false;
  }

  /// Looks up the available qualities, lets the user pick one and queues it.
  ///
  /// While yt-dlp reads the link a dialog with a Cancel button is shown.
  /// Cancel (or the system back gesture) closes it at once and abandons the
  /// lookup: its late result or error is ignored and no quality sheet appears.
  /// The lookup also gives up on its own after [infoTimeout]. If another
  /// screen was opened above the dialog meanwhile, the dialog is removed and
  /// the result is dropped (no sheet, no message).
  ///
  /// When the lookup fails because yt-dlp cannot run ([isEngineUnavailable])
  /// and [onEngineUnavailable] is given, that is called instead of showing
  /// the error (the Downloads screen then uses the YouTube path without yt-dlp).
  static Future<void> start(
    BuildContext context,
    WidgetRef ref,
    Uri uri, {
    VoidCallback? onQueued,
    VoidCallback? onNotificationDenied,
    Future<void> Function()? onEngineUnavailable,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final backend = ref.read(extractorBackendProvider);

    final requestId = 'info${DateTime.now().microsecondsSinceEpoch}';
    // Abandoned lookups must not keep yt-dlp working in the background.
    void stopLookup() => unawaited(backend.cancelInfo(requestId).catchError((_) {}));

    final outcome = await lookupWithDialog<ExtractorMetadata>(
      context,
      uri: uri,
      timeout: infoTimeout,
      lookup: () => backend.getInfo(uri.toString(), requestId: requestId),
      onAbandoned: stopLookup,
    );
    if (outcome == null || !context.mounted) return;

    final info = outcome.value;
    if (info == null) {
      if (onEngineUnavailable != null && isEngineUnavailable(outcome.error)) {
        await onEngineUnavailable();
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(outcome.error))));
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FormatSelectionSheet(
        metadata: info,
        onSelect: (choice) => _queue(context, ref, uri, info, choice, onQueued, onNotificationDenied),
      ),
    );
  }

  /// Runs [lookup] while the "Finding available qualities" dialog (with a
  /// Cancel button) is shown, and closes the dialog when it ends. Shared by
  /// the yt-dlp flow and the YouTube flow that needs no yt-dlp.
  ///
  /// Returns the result or the error (a [TimeoutException] after [timeout]),
  /// or null when the lookup was abandoned: the user closed the dialog
  /// (Cancel / back), the dialog was removed, another screen was opened above
  /// it, or the calling screen went away. A late result or error of an
  /// abandoned lookup is ignored. [onAbandoned] runs for an abandoned lookup
  /// and for one that timed out, so the work behind it can be stopped.
  static Future<LinkLookupOutcome<T>?> lookupWithDialog<T>(
    BuildContext context, {
    required Uri uri,
    required Future<T> Function() lookup,
    required Duration timeout,
    VoidCallback? onAbandoned,
  }) async {
    // Captured up front so the loading dialog is closed even if the calling
    // screen goes away while the lookup is still working.
    final navigator = Navigator.of(context, rootNavigator: true);

    // The dialog's future completes when its route is popped. We only pop it
    // ourselves after the lookup has finished, so if it completes first the
    // user closed it (Cancel / back) or the route was removed: give up.
    var dialogClosed = false;
    // The dialog's own route (known once it has been built), so that closing
    // it below can never pop some other route that ended up on top of it.
    Route<void>? dialogRoute;
    final closedByUser = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        dialogRoute ??= ModalRoute.of(dialogContext);
        return _FetchingInfoDialog(host: _displayHost(uri));
      },
    ).then((_) {
      dialogClosed = true;
      return LinkLookupOutcome<T>._cancelled();
    });

    // Future.sync: a lookup that throws synchronously is reported like any
    // other failure instead of escaping and leaving the dialog up.
    final running = Future<T>.sync(lookup).timeout(timeout).then<LinkLookupOutcome<T>>(
          (value) => LinkLookupOutcome<T>._value(value),
          onError: (Object e) => LinkLookupOutcome<T>._error(e),
        );

    // Whichever finishes first wins; the loser is ignored (Future.any keeps
    // listening to it, so a late error is never reported as unhandled).
    final outcome = await Future.any<LinkLookupOutcome<T>>([running, closedByUser]);
    final route = dialogRoute;
    // Also treat a dialog route that vanished without completing its future
    // (e.g. removed together with the screen below it) as "cancelled".
    if (outcome._cancelled || dialogClosed || (route != null && !route.isActive)) {
      onAbandoned?.call();
      return null;
    }
    if (outcome.error is TimeoutException) onAbandoned?.call();

    // Something was pushed above the dialog while the lookup was working (e.g.
    // the video player opened on the root navigator). The user has moved on:
    // read this before the dialog is removed, then treat the lookup as
    // abandoned instead of opening the quality sheet (or an error) behind or
    // over an unrelated screen.
    final movedOn = route != null && !route.isCurrent;
    _closeLoadingDialog(navigator, route);
    if (movedOn || !context.mounted) return null;
    return outcome;
  }

  /// Dismisses the "Finding available qualities" dialog after the lookup.
  /// [route] is null only if the dialog was never built (the lookup finished
  /// before the next frame); it is then still the top route.
  static void _closeLoadingDialog(NavigatorState navigator, Route<void>? route) {
    if (!navigator.mounted) return;
    if (route == null || route.isCurrent) {
      navigator.pop();
    } else if (route.isActive) {
      // Something was pushed above the dialog: remove just the dialog.
      navigator.removeRoute(route);
    }
  }

  /// "www.youtube.com" -> "youtube.com", "m.youtube.com" -> "youtube.com".
  static String _displayHost(Uri uri) => uri.host.replaceFirst(RegExp(r'^(www|m)\.'), '');

  static Future<void> _queue(
    BuildContext context,
    WidgetRef ref,
    Uri uri,
    ExtractorMetadata meta,
    FormatChoice choice,
    VoidCallback? onQueued,
    VoidCallback? onNotificationDenied,
  ) async {
    final granted = await ensureNotificationPermission();
    if (!context.mounted) return;
    if (!granted) onNotificationDenied?.call();
    if (!await confirmNotice(context, ref)) return;
    if (!context.mounted) return;

    // Read both before the next await: `ref` must not be used once the calling
    // screen is gone, but the queue itself is app-wide and should still start.
    final runner = ref.read(extractorDownloadRunnerProvider);
    final coordinator = ref.read(downloadQueueCoordinatorProvider.notifier);
    try {
      await runner.enqueue(meta: meta, pageUrl: uri.toString(), choice: choice);
    } catch (_) {
      // Called fire-and-forget from the quality sheet: an escaped error would
      // vanish without telling the user.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not add this download. Please try again.')),
        );
      }
      return;
    }
    coordinator.trigger();

    if (!context.mounted) return;
    onQueued?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added to Downloads: ${meta.title} (${choice.qualityLabel})')),
    );
  }
}

/// How one lookup run by [WebLinkDownloadFlow.lookupWithDialog] ended:
/// exactly one of [value] and [error] is set.
class LinkLookupOutcome<T> {
  const LinkLookupOutcome._value(T this.value)
      : error = null,
        _cancelled = false;
  const LinkLookupOutcome._error(Object this.error)
      : value = null,
        _cancelled = false;
  const LinkLookupOutcome._cancelled()
      : value = null,
        error = null,
        _cancelled = true;

  final T? value;
  final Object? error;

  /// The user closed the dialog before the lookup finished (never returned).
  final bool _cancelled;
}

/// "Finding available qualities..." card: a spinner in a soft brand halo,
/// the site being read and a Cancel button. Closing it (Cancel or the system
/// back gesture) is all Cancel does; [WebLinkDownloadFlow.start] notices the
/// closed dialog and abandons the lookup.
class _FetchingInfoDialog extends StatelessWidget {
  const _FetchingInfoDialog({required this.host});

  /// Site being read, e.g. "youtube.com" (empty when the link has no host).
  final String host;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final type = AppTypography.of(palette);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.giant40,
        vertical: AppSpacing.xxl24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxl24,
            AppSpacing.xxl24,
            AppSpacing.xxl24,
            AppSpacing.lg16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      palette.primaryBase.withValues(alpha: 0.28),
                      palette.primaryBase.withValues(alpha: 0.04),
                    ],
                  ),
                ),
                child: const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3, strokeCap: StrokeCap.round),
                ),
              ),
              const SizedBox(height: AppSpacing.lg16),
              Semantics(
                liveRegion: true,
                child: Text(
                  'Finding available qualities...',
                  textAlign: TextAlign.center,
                  style: type.bodyStrong,
                ),
              ),
              if (host.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm8),
                PillTag(text: host, icon: Icons.link_rounded, color: palette.accent),
              ],
              const SizedBox(height: AppSpacing.sm8),
              Text(
                'Long videos can take a little while.',
                textAlign: TextAlign.center,
                style: type.metadata,
              ),
              const SizedBox(height: AppSpacing.xl20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
