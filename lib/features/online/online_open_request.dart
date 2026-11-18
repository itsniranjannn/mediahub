import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'youtube_urls.dart';

/// Another screen asks the Online tab to open a YouTube page (a liked or
/// saved online song, say): it calls `open(uri)` on this provider's notifier
/// and then `context.go('/online')`. The Online screen loads the page and
/// clears the request.
///
/// Only YouTube pages are accepted (https; an http link is upgraded); any
/// other address is ignored, so nothing else can be loaded into the tab.
class OnlineOpenRequestNotifier extends Notifier<Uri?> {
  @override
  Uri? build() => null;

  /// Asks the Online tab to load [uri]. Returns false (and changes nothing)
  /// when [uri] is not a YouTube page.
  bool open(Uri uri) {
    if (!isYouTubePage(uri)) return false;
    state = uri.scheme.toLowerCase() == 'http' ? uri.replace(scheme: 'https') : uri;
    return true;
  }

  /// Same as [open], for a link held as text; false when it does not parse.
  bool openLink(String link) {
    final uri = Uri.tryParse(link.trim());
    return uri != null && open(uri);
  }

  /// The Online screen took the request.
  void clear() => state = null;
}

final onlineOpenRequestProvider =
    NotifierProvider<OnlineOpenRequestNotifier, Uri?>(OnlineOpenRequestNotifier.new);
