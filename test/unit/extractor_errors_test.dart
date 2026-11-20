import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/personal/extractor_errors.dart';

const _allCodes = [
  'HOST_NOT_ALLOWED',
  'LOGIN_REQUIRED',
  'PRIVATE_CONTENT',
  'DRM_PROTECTED',
  'NOT_FOUND',
  'NETWORK_ERROR',
  'PLAYLIST_NOT_SUPPORTED',
  'LIVE_NOT_SUPPORTED',
  'INFO_TIMEOUT',
  'AGE_RESTRICTED',
  'UNAVAILABLE',
  'BOT_CHECK',
  'FORMAT_UNAVAILABLE',
  'NO_MEDIA',
  'EXTRACTION_FAILED',
  'EMPTY_METADATA',
  'INIT_FAILED',
  'INIT_ERROR',
  'FILE_TOO_LARGE',
  'NO_OUTPUT',
  'CANCELLED',
  'SOMETHING_NEW',
];

void main() {
  test('no message asks the user to update the downloader (MediaHub does that itself now)', () {
    for (final code in _allCodes) {
      for (final text in [ExtractorErrors.lookupMessage(code), ExtractorErrors.downloadMessage('x_${code.toLowerCase()}')]) {
        expect(text.toLowerCase(), isNot(contains('settings')), reason: '$code: $text');
        expect(text.toLowerCase(), isNot(contains('update')), reason: '$code: $text');
        expect(text, isNot(contains('yt-dlp')), reason: '$code: $text');
        expect(text, isNot(contains('--')), reason: '$code: $text');
      }
    }
  });

  test('the owner\'s failure (Requested format is not available) reads as plain words', () {
    expect(
      ExtractorErrors.downloadMessage('x_extraction_failed'),
      'Could not fetch this video. The site may have changed. Tap Retry later.',
    );
    expect(
      ExtractorErrors.downloadMessage('x_format_unavailable'),
      'This video has no version that can be saved right now. Try again later.',
    );
  });

  test('private, age-restricted, unavailable and live videos each say why', () {
    expect(ExtractorErrors.downloadMessage('x_private_content'), 'This video is private and cannot be downloaded.');
    expect(ExtractorErrors.downloadMessage('x_age_restricted'), "This video is age-restricted, so it can't be downloaded.");
    expect(ExtractorErrors.lookupMessage('AGE_RESTRICTED'), "This video is age-restricted, so it can't be downloaded.");
    expect(ExtractorErrors.downloadMessage('x_unavailable'),
        'This video is unavailable. It may have been removed or blocked in your country.');
    expect(ExtractorErrors.downloadMessage('x_live_not_supported'),
        "Live streams can't be downloaded. Try again after the stream has ended.");
    expect(ExtractorErrors.lookupMessage('BOT_CHECK'), contains('Try again later'));
    expect(ExtractorErrors.lookupMessage('NO_MEDIA'), 'This link has no video or audio to save.');
  });

  test('the messages a download row showed before keep their words', () {
    expect(ExtractorErrors.downloadMessage('x_login_required'),
        'This video needs a login. Only public videos can be downloaded.');
    expect(ExtractorErrors.downloadMessage('x_drm_protected'), 'This content is DRM protected and cannot be downloaded.');
    expect(ExtractorErrors.downloadMessage('x_not_found'), 'The video was not found. It may have been removed.');
    expect(ExtractorErrors.downloadMessage('x_file_too_large'), 'The video is larger than the 2 GB limit.');
    expect(ExtractorErrors.downloadMessage('x_network_error'),
        'Network problem while downloading. Check your connection and retry.');
    expect(ExtractorErrors.downloadMessage('x_no_output'), 'The downloader finished but produced no file. Please retry.');
    expect(ExtractorErrors.downloadMessage('x_host_not_allowed'),
        'This website is not supported by the web link downloader.');
    expect(ExtractorErrors.downloadMessage('x_init_failed'), 'The downloader engine could not start. Please retry.');
    expect(ExtractorErrors.downloadMessage('x_error'), 'Web link download failed. Tap Retry to try again.');
  });

  test('which failures update yt-dlp, and which try the YouTube path without it', () {
    for (final code in ['EXTRACTION_FAILED', 'FORMAT_UNAVAILABLE', 'BOT_CHECK']) {
      expect(ExtractorErrors.updateMayHelp, contains(code));
      expect(ExtractorErrors.youtubeFallbackMayHelp, contains(code));
    }
    // yt-dlp cannot start: an update does not help, the YouTube path may.
    expect(ExtractorErrors.updateMayHelp, isNot(contains('INIT_FAILED')));
    expect(ExtractorErrors.youtubeFallbackMayHelp, contains('INIT_FAILED'));
    // YouTube limits this phone for a while: no update (it would not help), but
    // the file YouTube serves directly may still come through.
    expect(ExtractorErrors.updateMayHelp, isNot(contains('RATE_LIMITED')));
    expect(ExtractorErrors.youtubeFallbackMayHelp, contains('RATE_LIMITED'));
    // About the video itself: neither helps.
    for (final code in [
      'PRIVATE_CONTENT',
      'AGE_RESTRICTED',
      'UNAVAILABLE',
      'LIVE_NOT_SUPPORTED',
      'LOGIN_REQUIRED',
      'NETWORK_ERROR',
      'CANCELLED',
      'NOT_FOUND',
      'DRM_PROTECTED',
      'FILE_TOO_LARGE',
      'NO_MEDIA',
    ]) {
      expect(ExtractorErrors.updateMayHelp, isNot(contains(code)), reason: code);
      expect(ExtractorErrors.youtubeFallbackMayHelp, isNot(contains(code)), reason: code);
    }
  });

  // Review finding: YouTube's "Video unavailable. This content isn't
  // available, try again later" (a rate limit) was told to the user as a
  // removed or blocked video.
  test('a rate limit says to wait, not that the video is gone', () {
    final m = ExtractorErrors.downloadMessage('x_rate_limited');
    expect(m, contains('Try again in an hour'));
    expect(m, isNot(contains('removed')));
    expect(ExtractorErrors.lookupMessage('RATE_LIMITED'), m);
  });

  // Seen on a Wi-Fi that inspects HTTPS: every yt-dlp run failed with
  // CERTIFICATE_VERIFY_FAILED and was told as "the site may have changed".
  test('a network that breaks the secure connection says so, and nothing retries it', () {
    const m = 'This network is blocking a secure connection to the site. Try another Wi-Fi or mobile data.';
    expect(ExtractorErrors.lookupMessage('NETWORK_BLOCKED'), m);
    expect(ExtractorErrors.downloadMessage('x_network_blocked'), m);
    expect(ExtractorErrors.updateMayHelp, isNot(contains('NETWORK_BLOCKED')));
    expect(ExtractorErrors.youtubeFallbackMayHelp, isNot(contains('NETWORK_BLOCKED')));
  });
}
