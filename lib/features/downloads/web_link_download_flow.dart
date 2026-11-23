import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../app/theme/app_palette.dart';
import '../../core/downloads/known_platform_checker.dart';
import '../../core/logging/diagnostics_service.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/platform_info.dart';
import '../../personal/extractor_auto_updater.dart';
import '../../personal/extractor_backend.dart';
import '../../personal/extractor_errors.dart';
import '../../personal/extractor_hosts.dart';
import '../../personal/format_options.dart';
import '../../personal/format_selection_sheet.dart';
import '../../personal/personal_tools_notifier.dart';
import '../../shared/widgets/ui_kit.dart';
import 'download_providers.dart';
import 'downloads_notifier.dart';
import 'fast_youtube_extractor_resolver.dart';
import 'mobile_data_guard.dart';

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
  static const String _tooSlowMessage = ExtractorErrors.tooSlow;

  /// Plain words for anything a lookup can end with. yt-dlp's own text is
  /// never shown here (MediaHub updates yt-dlp by itself, so there is no
  /// "update the downloader" advice either).
  static String friendlyError(Object? e) {
    if (e is ExtractorException) return ExtractorErrors.lookupMessage(e.code);
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
    if (e is ExtractorException) return ExtractorErrors.youtubeFallbackMayHelp.contains(e.code);
    return false;
  }

  /// A quality lookup that failed (offline, too slow, a blocked network, a
  /// link problem): the message stays on screen until it is closed or
  /// [onRetry] is tapped, so the lookup never just ends without a word.
  static void showLookupFailure(ScaffoldMessengerState messenger, String message, {VoidCallback? onRetry}) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('lookup_failure'),
          content: Text(message),
          persist: true,
          showCloseIcon: true,
          action: onRetry == null ? null : SnackBarAction(label: 'Retry', onPressed: onRetry),
        ),
      );
  }

  /// Reads the qualities of [uri]. When that fails in a way a newer yt-dlp
  /// may fix, yt-dlp is updated (at most every 12 hours, never while a web
  /// link download runs) and the link read once more. Each read gives up
  /// after [infoTimeout]. [abandoned] turns true once the user closed the
  /// dialog: nothing more is started then. [onGaveUp] runs when a read timed
  /// out, so yt-dlp can be told to stop.
  @visibleForTesting
  static Future<ExtractorMetadata> lookupWithUpdate({
    required ExtractorBackend backend,
    required ExtractorAutoUpdater updater,
    required Uri uri,
    required String requestId,
    required bool Function() abandoned,
    bool downloadsRunning = false,
    VoidCallback? onGaveUp,
  }) async {
    // Every lookup goes to Settings → Diagnostics (the host, how long it took
    // and, when it failed, the code and yt-dlp's short reason), so a phone
    // that cannot read links can be told apart from a site that changed.
    final watch = Stopwatch()..start();
    Future<ExtractorMetadata> read() async {
      try {
        final meta = await backend.getInfo(uri.toString(), requestId: requestId).timeout(infoTimeout);
        DiagnosticsService.instance.logEvent('extractor_lookup_ok', {
          'host': uri.host,
          'ms': watch.elapsedMilliseconds,
        });
        return meta;
      } on TimeoutException {
        DiagnosticsService.instance.logEvent('extractor_lookup_failed', {
          'host': uri.host,
          'code': 'TIMEOUT',
          'ms': watch.elapsedMilliseconds,
        });
        onGaveUp?.call();
        rethrow;
      } on ExtractorException catch (e) {
        DiagnosticsService.instance.logEvent('extractor_lookup_failed', {
          'host': uri.host,
          'code': e.code,
          if (e.details != null) 'reason': e.details,
          'ms': watch.elapsedMilliseconds,
        });
        rethrow;
      }
    }

    try {
      return await read();
    } on ExtractorException catch (e) {
      if (!ExtractorErrors.updateMayHelp.contains(e.code) || abandoned()) rethrow;
      final outcome = await updater.updateAfterFailure(otherDownloadsRunning: downloadsRunning);
      DiagnosticsService.instance.logEvent('extractor_auto_update', {'outcome': outcome.name, 'after': 'lookup'});
      if (outcome != ExtractorUpdateOutcome.updated || abandoned()) rethrow;
      return read();
    }
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
  ///
  /// A link to a site yt-dlp may not read ([ExtractorHosts]) never reaches
  /// it: [onOtherSite] is called instead (the Downloads screen then checks
  /// whether the link is a direct audio or video file), or, without it, the
  /// user is told the site is not supported.
  static Future<void> start(
    BuildContext context,
    WidgetRef ref,
    Uri uri, {
    VoidCallback? onQueued,
    VoidCallback? onNotificationDenied,
    Future<void> Function()? onEngineUnavailable,
    Future<void> Function()? onOtherSite,
    VoidCallback? onRetry,
  }) async {
    final messenger = ScaffoldMessenger.of(context);

    // A Spotify song, album or playlist can never be saved: said at once
    // instead of after a long lookup that ends in "DRM protected".
    final protectedReason = KnownPlatformChecker.protectedContentMessage(uri);
    if (protectedReason != null) {
      // The Downloads screen already says it under the link.
      if (ref.read(inspectionProvider).errorMessage != protectedReason) {
        messenger.showSnackBar(SnackBar(content: Text(protectedReason)));
      }
      return;
    }

    // Any other site: the direct-link engine, which saves a link that points
    // straight at an audio or video file.
    if (!ExtractorHosts.isAllowed(uri)) {
      if (onOtherSite != null) {
        await onOtherSite();
      } else {
        messenger.showSnackBar(const SnackBar(content: Text(ExtractorErrors.hostNotAllowed)));
      }
      return;
    }

    final backend = ref.read(extractorBackendProvider);
    // Read now: `ref` must not be used once the calling screen is gone.
    final updater = ref.read(extractorAutoUpdaterProvider);
    final downloadsRunning = ref.read(extractorRunningDownloadsProvider) > 0;

    final requestId = 'info${DateTime.now().microsecondsSinceEpoch}';
    var stopped = false;
    // Abandoned lookups must not keep yt-dlp working in the background.
    void stopLookup() {
      if (stopped) return;
      stopped = true;
      unawaited(backend.cancelInfo(requestId).catchError((_) {}));
    }

    final outcome = await lookupWithDialog<ExtractorMetadata>(
      context,
      uri: uri,
      // Each read has its own [infoTimeout]; this covers two reads and a
      // yt-dlp update in between.
      timeout: infoTimeout * 2 + updater.updateTimeout,
      lookup: () async {
        // Fast path for YouTube: use native Dart youtube_explode_dart manifest
        // fetching over HTTPS (~1s), bypassing Python/yt-dlp startup overhead.
        try {
          final fastMeta = await FastYoutubeExtractorResolver.resolve(uri);
          if (fastMeta != null && fastMeta.formats.isNotEmpty) {
            DiagnosticsService.instance.logEvent('fast_youtube_lookup_ok', {
              'host': uri.host,
            });
            return fastMeta;
          }
        } catch (_) {
          // If fast lookup throws or fails, transparently fall through to yt-dlp.
        }

        return lookupWithUpdate(
          backend: backend,
          updater: updater,
          uri: uri,
          requestId: requestId,
          abandoned: () => stopped,
          downloadsRunning: downloadsRunning,
          onGaveUp: stopLookup,
        );
      },
      onAbandoned: stopLookup,
    );
    if (outcome == null || !context.mounted) return;

    final info = outcome.value;
    if (info == null) {
      final error = outcome.error;
      if (error is ExtractorException && error.code == 'HOST_NOT_ALLOWED' && onOtherSite != null) {
        await onOtherSite();
        return;
      }
      if (onEngineUnavailable != null && isEngineUnavailable(error)) {
        await onEngineUnavailable();
        return;
      }
      showLookupFailure(messenger, friendlyError(error), onRetry: onRetry);
      return;
    }

    await showModalBottomSheet<void>(
      // Over the Ink Dock: the sheet's barrier covers and dims it too.
      useRootNavigator: true,
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
    if (!await confirmBigDownloadOnMobileData(context, ref, choice.estimatedBytes)) return;
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
