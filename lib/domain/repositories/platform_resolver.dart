// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
enum SourceCapability {
  preview,
  download,
  audioOnly,
  videoOnly,
  trim,
  metadata,
}

class MediaFormatInfo {
  final String? container;
  final String? codec;
  final int? bitrate;
  final int? sizeBytes;

  const MediaFormatInfo({
    this.container,
    this.codec,
    this.bitrate,
    this.sizeBytes,
  });
}

class SourceInfo {
  final String providerId;
  final Uri uri;
  final Set<SourceCapability> capabilities;
  final List<MediaFormatInfo> formats;
  final List<String> restrictions;
  final String? humanReadableReason;
  final String? suggestedFilename;
  final String? contentType;
  final int? contentLength;
  final bool supportsRange;

  const SourceInfo({
    required this.providerId,
    required this.uri,
    required this.capabilities,
    this.formats = const [],
    this.restrictions = const [],
    this.humanReadableReason,
    this.suggestedFilename,
    this.contentType,
    this.contentLength,
    this.supportsRange = false,
  });

  bool get isDownloadable => capabilities.contains(SourceCapability.download);
}

abstract class PlatformResolver {
  bool canHandle(Uri uri);
  Future<SourceInfo> inspect(Uri uri);
}

