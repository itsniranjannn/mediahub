// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/url_policy.dart';
import 'download_link_inbox.dart';

/// What "Share to MediaHub" made of a shared text: a link for Downloads, or
/// a plain-language reason it was not taken.
class SharedLinkOutcome {
  const SharedLinkOutcome.accepted(String this.url) : message = null;
  const SharedLinkOutcome.rejected(String this.message) : url = null;

  /// The https link (checked by [UrlPolicy]) to hand to Downloads.
  final String? url;

  /// Why nothing was taken, for a snackbar.
  final String? message;

  bool get isAccepted => url != null;
}

/// Messages for the user (kept here so tests and the UI agree).
abstract final class SharedLinkMessages {
  static const noLink = 'No link to download in what was shared.';
  static const notSecure = 'Only secure https links can be downloaded.';
  static const blocked = 'That link cannot be downloaded.';
}

final RegExp _linkPattern = RegExp(r'''\b(https?)://[^\s<>"'`]+''', caseSensitive: false);

/// Trailing punctuation that ends a sentence rather than the link
/// ("Watch this: https://x.com/a." or "(https://x.com/a)").
final RegExp _trailingPunctuation = RegExp(r'''[.,;:!?)\]}'"]+$''');

/// Picks the first https link out of [text] (a caption, a message, a bare
/// link) and checks it with [UrlPolicy]: https only, no private or loopback
/// hosts, no credentials, no odd ports. Nothing else in the text is used.
SharedLinkOutcome parseSharedText(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const SharedLinkOutcome.rejected(SharedLinkMessages.noLink);
  var sawInsecure = false;
  for (final match in _linkPattern.allMatches(trimmed)) {
    final scheme = match.group(1)!.toLowerCase();
    if (scheme != 'https') {
      sawInsecure = true;
      continue;
    }
    var candidate = match.group(0)!;
    // Keep a ")" that closes a "(" inside the link (Wikipedia style).
    final stripped = candidate.replaceFirst(_trailingPunctuation, '');
    if (candidate.endsWith(')') && '('.allMatches(candidate).length >= ')'.allMatches(candidate).length) {
      candidate = candidate.replaceFirst(RegExp(r'''[.,;:!?\]}'"]+$'''), '');
    } else {
      candidate = stripped;
    }
    final result = UrlPolicy.validate(candidate);
    if (!result.isValid) return const SharedLinkOutcome.rejected(SharedLinkMessages.blocked);
    return SharedLinkOutcome.accepted(result.normalizedUri.toString());
  }
  return SharedLinkOutcome.rejected(sawInsecure ? SharedLinkMessages.notSecure : SharedLinkMessages.noLink);
}

/// Shared texts from the platform ("mediahub/shared_link" on Android).
abstract class SharedTextSource {
  Stream<String> get texts;
}

class PlatformSharedTextSource implements SharedTextSource {
  PlatformSharedTextSource() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText' && call.arguments is String) _add(call.arguments as String);
      return null;
    });
    // A share that started MediaHub waits natively until this side listens.
    unawaited(_takePending());
  }

  static const MethodChannel _channel = MethodChannel('mediahub/shared_link');
  final StreamController<String> _controller = StreamController<String>.broadcast();
  final List<String> _early = [];

  void _add(String text) {
    if (_controller.hasListener) {
      _controller.add(text);
    } else {
      _early.add(text);
    }
  }

  Future<void> _takePending() async {
    try {
      final text = await _channel.invokeMethod<String>('takePending');
      if (text != null) _add(text);
    } catch (_) {
      // Not Android, or no native side (tests).
    }
  }

  @override
  Stream<String> get texts {
    if (_early.isEmpty) return _controller.stream;
    final early = List<String>.of(_early);
    _early.clear();
    return Stream<String>.multi((sink) {
      early.forEach(sink.add);
      final sub = _controller.stream.listen(sink.add, onError: sink.addError, onDone: sink.close);
      sink.onCancel = sub.cancel;
    });
  }
}

final sharedTextSourceProvider = Provider<SharedTextSource>((ref) => PlatformSharedTextSource());

/// Handles one shared [text]: a good link goes to the Downloads inbox (the
/// Downloads tab takes it once it is on screen and the app is unlocked, and
/// starts the quality lookup); anything else returns the message to show.
/// Returns null when the link was handed on.
String? acceptSharedText(Ref ref, String text) {
  final outcome = parseSharedText(text);
  if (!outcome.isAccepted) return outcome.message;
  ref.read(downloadLinkInboxProvider.notifier).send(PendingDownloadLink(outcome.url!));
  return null;
}

/// Listens for shared texts: a good link is handed on and [openDownloads]
/// runs; otherwise [showMessage] gets the reason. Cancel the result to stop.
StreamSubscription<String> listenForSharedLinks(
  Ref ref, {
  required void Function() openDownloads,
  required void Function(String message) showMessage,
}) {
  return ref.read(sharedTextSourceProvider).texts.listen((text) {
    final problem = acceptSharedText(ref, text);
    if (problem == null) {
      openDownloads();
    } else {
      showMessage(problem);
    }
  });
}
