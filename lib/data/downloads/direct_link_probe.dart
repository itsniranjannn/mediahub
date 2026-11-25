// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core/downloads/content_disposition.dart';
import '../../core/downloads/media_kind_classifier.dart';
import '../../core/downloads/media_sniffer.dart';
import '../../core/security/safe_filename.dart';
import '../../core/security/safe_http_client.dart';
import '../../domain/repositories/platform_resolver.dart';
import 'download_engine.dart';

/// What the first bytes of a link showed.
class DirectLinkFacts {
  const DirectLinkFacts({
    required this.finalUri,
    required this.statusCode,
    this.contentType,
    this.totalBytes,
    this.supportsRange = false,
    this.fileName,
    this.sniffedMime,
  });

  /// Where the link led after its redirects.
  final Uri finalUri;
  final int statusCode;

  /// The server's own type (no parameters, lower case).
  final String? contentType;

  /// The whole file's size, when the server said.
  final int? totalBytes;
  final bool supportsRange;

  /// The best file name found: the server's `Content-Disposition`, else the
  /// last part of the address (after redirects) that names a media file.
  final String? fileName;

  /// The file type its first bytes show, or null when they are not media.
  final String? sniffedMime;
}

/// Looks at the first bytes of a direct link to see whether it is a media
/// file, whatever the server calls it.
///
/// Many real download links say little about the file: no extension
/// (`/get?id=123`), a generic type (`application/octet-stream`,
/// `binary/octet-stream`), a name only in `Content-Disposition` or only at
/// the end of a redirect, or a `HEAD` request the server refuses. One small
/// `GET` for the first [probeBytes] bytes (a range when the server allows it;
/// otherwise the reply is closed after those bytes) settles it by the
/// file's magic bytes. It goes through [SafeHttpClient], so every safety
/// rule still holds: https only, no private addresses on any hop, at most
/// [probeBytes] (plus one network chunk) ever read.
class DirectLinkProbe {
  DirectLinkProbe({SafeHttpClient? client, this.timeout = const Duration(seconds: 12)})
      : _client = client ?? SafeHttpClient();

  final SafeHttpClient _client;
  final Duration timeout;

  static const int probeBytes = 4096;

  /// The facts about [uri], or null when it could not be reached.
  Future<DirectLinkFacts?> probe(Uri uri) async {
    SafeStreamResponse? response;
    try {
      response = await _client
          .openStream(uri, headers: const {'Range': 'bytes=0-${probeBytes - 1}'}, maxBodySize: 1024 * 1024)
          .timeout(timeout);
      final status = response.statusCode;
      final headers = response.headers;
      final bytes = BytesBuilder(copy: false);
      if (status < 400) {
        await for (final chunk in response.body.timeout(timeout)) {
          bytes.add(chunk);
          if (bytes.length >= probeBytes) break;
        }
      }
      final head = bytes.takeBytes();
      final type = headers.value(HttpHeaders.contentTypeHeader)?.split(';').first.trim().toLowerCase();
      final contentRange = headers.value('content-range');
      int? total;
      if (contentRange != null && contentRange.contains('/')) {
        total = int.tryParse(contentRange.split('/').last.trim());
      } else if (status == 200) {
        total = int.tryParse(headers.value(HttpHeaders.contentLengthHeader) ?? '');
      }
      final acceptRanges = headers.value(HttpHeaders.acceptRangesHeader)?.toLowerCase();
      return DirectLinkFacts(
        finalUri: response.finalUri,
        statusCode: status,
        contentType: (type == null || type.isEmpty) ? null : type,
        totalBytes: total,
        supportsRange: status == 206 || acceptRanges == 'bytes',
        fileName: bestFileName(
          contentDisposition: headers.value('content-disposition'),
          finalUri: response.finalUri,
          originalUri: uri,
        ),
        sniffedMime: head.length >= 4 ? MediaSniffer.sniff(head) : null,
      );
    } catch (_) {
      return null;
    } finally {
      response?.close();
    }
  }

  /// The server's name for the file, else the last part of the address that
  /// names a media file (the final one after redirects first), else the last
  /// part of the final address. Never throws on odd percent signs.
  static String? bestFileName({String? contentDisposition, required Uri finalUri, required Uri originalUri}) {
    final fromHeader = ContentDisposition.fileName(contentDisposition);
    if (fromHeader != null && fromHeader.isNotEmpty) return fromHeader;
    String? last(Uri u) {
      final segments = u.pathSegments.where((s) => s.trim().isNotEmpty).toList();
      return segments.isEmpty ? null : segments.last; // already decoded by Uri
    }

    bool isMedia(String? name) {
      final ext = MediaKindClassifier.extensionOf(name);
      return MediaKindClassifier.audioExtensions.contains(ext) || MediaKindClassifier.videoExtensions.contains(ext);
    }

    final finalName = last(finalUri);
    final originalName = last(originalUri);
    if (isMedia(finalName)) return finalName;
    if (isMedia(originalName)) return originalName;
    return finalName ?? originalName;
  }

  /// [info] (the direct-link check) completed with what the first bytes
  /// show, when that is needed:
  /// - the check could not decide or failed outright (no media type or
  ///   extension, or an address it could not read): the first bytes decide;
  /// - the link is media but its name has no media extension: the server's
  ///   own name, or the name at the end of the redirects, is used.
  /// Returns [info] unchanged when nothing better was found, and null only
  /// when there was no [info] and the link is not media either.
  Future<SourceInfo?> refine(SourceInfo? info, Uri uri) async {
    if (info != null && !needsProbe(info)) return info;
    if (info != null && info.restrictions.contains('policy_violation')) return info;
    final facts = await probe(info?.uri ?? uri);
    if (facts == null || facts.statusCode >= 400) return info;
    final sniffed = facts.sniffedMime;

    if (info != null && info.isDownloadable) {
      // Media already: only a better name.
      final name = facts.fileName;
      if (name == null) return info;
      final ext = sniffed == null ? '' : _extensionFor(sniffed);
      final better = SafeFilename.sanitize(MediaKindClassifier.nameWithMediaExtension(SafeFilename.sanitize(name), ext));
      if (!_hasMediaExtension(better)) return info;
      return _copy(info, suggestedFilename: better);
    }

    if (sniffed == null) return info; // a web page or another kind of file
    final rawName = facts.fileName;
    final name = SafeFilename.sanitize(
      MediaKindClassifier.nameWithMediaExtension(SafeFilename.sanitize(rawName, defaultExtension: 'bin'), _extensionFor(sniffed)),
    );
    final isVideo = sniffed.startsWith('video/');
    return SourceInfo(
      providerId: 'direct',
      uri: info?.uri ?? uri,
      capabilities: {
        SourceCapability.metadata,
        SourceCapability.download,
        SourceCapability.preview,
        isVideo ? SourceCapability.videoOnly : SourceCapability.audioOnly,
      },
      formats: [MediaFormatInfo(container: _extensionFor(sniffed), sizeBytes: facts.totalBytes ?? info?.contentLength)],
      suggestedFilename: name,
      contentType: sniffed,
      contentLength: facts.totalBytes ?? info?.contentLength,
      supportsRange: facts.supportsRange || (info?.supportsRange ?? false),
    );
  }

  /// True when [info] leaves something the first bytes can settle.
  static bool needsProbe(SourceInfo info) {
    if (info.restrictions.contains('policy_violation')) return false;
    if (!info.isDownloadable) {
      // A web page is a web page; anything else the first bytes decide.
      // (An address that did not answer at all is not asked again.)
      return info.restrictions.contains('unsupported_media_type');
    }
    return !_hasMediaExtension(info.suggestedFilename);
  }

  static bool _hasMediaExtension(String? name) {
    final ext = MediaKindClassifier.extensionOf(name);
    return MediaKindClassifier.audioExtensions.contains(ext) || MediaKindClassifier.videoExtensions.contains(ext);
  }

  /// The extension for [mime] (none for a type with no usual one).
  static String _extensionFor(String mime) {
    final ext = DownloadEngine.extensionForMime(mime);
    return ext == 'bin' ? '' : ext;
  }

  static SourceInfo _copy(SourceInfo info, {String? suggestedFilename}) => SourceInfo(
        providerId: info.providerId,
        uri: info.uri,
        capabilities: info.capabilities,
        formats: info.formats,
        restrictions: info.restrictions,
        humanReadableReason: info.humanReadableReason,
        suggestedFilename: suggestedFilename ?? info.suggestedFilename,
        contentType: info.contentType,
        contentLength: info.contentLength,
        supportsRange: info.supportsRange,
      );
}
