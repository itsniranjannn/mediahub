// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A link another screen hands to Downloads, e.g. the Online tab's "Download"
/// button for the YouTube video that is open.
class PendingDownloadLink {
  const PendingDownloadLink(this.url, {this.title, this.inspect = true});

  /// The https link to download (already cleaned of tracking parameters).
  final String url;

  /// Optional title for snackbars and the format sheet header.
  final String? title;

  /// Start the link lookup (format choice) right away instead of only
  /// filling the field.
  final bool inspect;
}

/// One-slot inbox: the sender calls [send] and switches to the Downloads tab;
/// the Downloads screen reads the link with [take], which empties the slot so
/// the link is handled exactly once.
///
/// The Downloads screen takes it on its first build and whenever a new link
/// arrives, but only while its tab is on screen: a link sent while Downloads
/// is in the background waits here until the tab is shown. A newer [send]
/// replaces a link nobody took yet. If a quality lookup or choice is already
/// running, the link is put in the link field (with a note) instead of
/// starting a second lookup on top.
class DownloadLinkInbox extends Notifier<PendingDownloadLink?> {
  @override
  PendingDownloadLink? build() => null;

  void send(PendingDownloadLink link) => state = link;

  PendingDownloadLink? take() {
    final link = state;
    if (link != null) state = null;
    return link;
  }
}

final downloadLinkInboxProvider =
    NotifierProvider<DownloadLinkInbox, PendingDownloadLink?>(DownloadLinkInbox.new);
