import 'dart:io';

import '../../core/security/safe_filename.dart';
import '../../core/security/safe_http_client.dart';
import '../../core/security/url_policy.dart';
import '../../domain/repositories/platform_resolver.dart';

class DirectUrlResolver implements PlatformResolver {
  final SafeHttpClient _client;

  DirectUrlResolver({SafeHttpClient? client})
      : _client = client ?? SafeHttpClient();

  static const Set<String> _mediaExtensions = {
    // Audio
    'mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus',
    // Video
    'mp4', 'mkv', 'webm', 'mov', 'avi', 'm4v', '3gp',
  };

  @override
  bool canHandle(Uri uri) {
    // DirectUrlResolver is the universal fallback for direct HTTPS media URLs
    return uri.scheme.toLowerCase() == 'https';
  }

  @override
  Future<SourceInfo> inspect(Uri uri) async {
    // 1. Check URL policy upfront
    final policyResult = UrlPolicy.validate(uri.toString());
    if (!policyResult.isValid) {
      return SourceInfo(
        providerId: 'direct',
        uri: uri,
        capabilities: {},
        restrictions: const ['policy_violation'],
        humanReadableReason: policyResult.message,
      );
    }

    final validatedUri = policyResult.normalizedUri!;
    SafeHttpResponse? response;

    // 2. Try HEAD first
    try {
      response = await _client.request(
        validatedUri,
        method: 'HEAD',
      );
      // Some servers return 405 Method Not Allowed or 403 on HEAD
      if (response.statusCode >= 400) {
        response = null;
      }
    } catch (_) {
      response = null;
    }

    // 3. Fall back to GET with Range: bytes=0-0 if HEAD failed
    if (response == null) {
      try {
        response = await _client.request(
          validatedUri,
          method: 'GET',
          headers: const {'Range': 'bytes=0-0'},
          maxBodySize: 64 * 1024, // only reading the first byte/chunk
        );
      } catch (e) {
        return SourceInfo(
          providerId: 'direct',
          uri: validatedUri,
          capabilities: {},
          restrictions: const ['unreachable'],
          humanReadableReason: 'Failed to inspect URL: $e',
        );
      }
    }

    if (response.statusCode >= 400) {
      return SourceInfo(
        providerId: 'direct',
        uri: validatedUri,
        capabilities: {},
        restrictions: ['http_${response.statusCode}'],
        humanReadableReason: 'Server returned HTTP error ${response.statusCode} (${response.reasonPhrase})',
      );
    }

    // 4. Extract headers
    final contentType = response.headers.value(HttpHeaders.contentTypeHeader)?.split(';').first.trim().toLowerCase();
    final acceptRanges = response.headers.value(HttpHeaders.acceptRangesHeader)?.toLowerCase();
    final contentRange = response.headers.value('content-range');
    final supportsRange = acceptRanges == 'bytes' || contentRange != null || response.statusCode == 206;

    // Parse Content-Length or Content-Range
    int? contentLength;
    if (contentRange != null && contentRange.contains('/')) {
      final totalStr = contentRange.split('/').last.trim();
      contentLength = int.tryParse(totalStr);
    }
    if (contentLength == null) {
      final clHeader = response.headers.value(HttpHeaders.contentLengthHeader);
      if (clHeader != null) {
        contentLength = int.tryParse(clHeader);
      }
    }

    // Filename suggestion from Content-Disposition or URL path
    String? filenameSuggestion;
    final contentDisp = response.headers.value('content-disposition');
    if (contentDisp != null) {
      final cdPattern = RegExp(r'''filename\*?=(?:UTF-8'')?["']?([^"';\n]+)["']?''', caseSensitive: false);
      final match = cdPattern.firstMatch(contentDisp);
      if (match != null) {
        filenameSuggestion = Uri.decodeComponent(match.group(1)!.trim());
      }
    }
    if (filenameSuggestion == null || filenameSuggestion.isEmpty) {
      final segments = validatedUri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        filenameSuggestion = Uri.decodeComponent(segments.last);
      }
    }
    final sanitizedFilename = SafeFilename.sanitize(filenameSuggestion);

    // 5. Check if downloadable based on content-type or media extension
    bool isDownloadable = false;
    String? reason;
    final fileExt = sanitizedFilename.contains('.') ? sanitizedFilename.split('.').last.toLowerCase() : '';

    final isAudioMime = contentType != null && contentType.startsWith('audio/');
    final isVideoMime = contentType != null && contentType.startsWith('video/');
    final isOctetStream = contentType == 'application/octet-stream';

    if (isAudioMime || isVideoMime) {
      isDownloadable = true;
    } else if (isOctetStream && _mediaExtensions.contains(fileExt)) {
      isDownloadable = true;
    } else if (_mediaExtensions.contains(fileExt)) {
      isDownloadable = true;
    } else {
      isDownloadable = false;
      reason = 'Unsupported media type: ${contentType ?? 'unknown'} ($sanitizedFilename)';
    }

    final capabilities = <SourceCapability>{
      SourceCapability.metadata,
      if (isDownloadable) SourceCapability.download,
      if (isDownloadable) SourceCapability.preview,
      if (isAudioMime || (isDownloadable && const ['mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus'].contains(fileExt)))
        SourceCapability.audioOnly,
      if (isVideoMime || (isDownloadable && const ['mp4', 'mkv', 'webm', 'mov', 'avi'].contains(fileExt)))
        SourceCapability.videoOnly,
    };

    final formats = <MediaFormatInfo>[
      MediaFormatInfo(
        container: fileExt.isNotEmpty ? fileExt : contentType?.split('/').last,
        sizeBytes: contentLength,
      ),
    ];

    return SourceInfo(
      providerId: 'direct',
      uri: validatedUri,
      capabilities: capabilities,
      formats: formats,
      restrictions: isDownloadable ? const [] : const ['unsupported_media_type'],
      humanReadableReason: reason,
      suggestedFilename: sanitizedFilename,
      contentType: contentType,
      contentLength: contentLength,
      supportsRange: supportsRange,
    );
  }
}
