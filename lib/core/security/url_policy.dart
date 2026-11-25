// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:io';
import 'ip_guard.dart';

enum UrlPolicyErrorCode {
  tooLong,
  invalidScheme,
  emptyHost,
  invalidHost,
  userinfoNotAllowed,
  nonStandardPort,
  blockedIpLiteral,
  invalidUri,
}

class UrlPolicyResult {
  final bool isValid;
  final Uri? normalizedUri;
  final UrlPolicyErrorCode? errorCode;
  final String? message;

  const UrlPolicyResult._({
    required this.isValid,
    this.normalizedUri,
    this.errorCode,
    this.message,
  });

  factory UrlPolicyResult.success(Uri normalizedUri) {
    return UrlPolicyResult._(
      isValid: true,
      normalizedUri: normalizedUri,
    );
  }

  factory UrlPolicyResult.failure(UrlPolicyErrorCode code, String message) {
    return UrlPolicyResult._(
      isValid: false,
      errorCode: code,
      message: message,
    );
  }
}

class UrlPolicy {
  UrlPolicy._();

  static const int maxUrlLength = 2048;

  /// Validates and normalizes [rawUrl] according to security policies:
  /// - Length <= 2048 chars
  /// - HTTPS scheme only (http and other schemes rejected)
  /// - No userinfo (username / password)
  /// - Port must be default (443) or omitted
  /// - Host non-empty and contains no control characters (ASCII 0..31 and 127)
  /// - IP literals (IPv4 or IPv6) are checked against [IpGuard] and blocked if private/reserved
  /// - Returns [UrlPolicyResult] with typed error code and plain-language message
  static UrlPolicyResult validate(String rawUrl) {
    if (rawUrl.length > maxUrlLength) {
      return UrlPolicyResult.failure(
        UrlPolicyErrorCode.tooLong,
        'URL exceeds maximum allowed length of $maxUrlLength characters.',
      );
    }

    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return UrlPolicyResult.failure(
        UrlPolicyErrorCode.invalidUri,
        'URL cannot be empty.',
      );
    }

    // Check for control characters anywhere in the raw URL upfront
    for (int i = 0; i < trimmed.length; i++) {
      final codeUnit = trimmed.codeUnitAt(i);
      if (codeUnit < 32 || codeUnit == 127) {
        return UrlPolicyResult.failure(
          UrlPolicyErrorCode.invalidHost,
          'URL contains invalid control characters.',
        );
      }
    }

    Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (e) {
      return UrlPolicyResult.failure(
        UrlPolicyErrorCode.invalidUri,
        'Malformed URL format.',
      );
    }

    // Check scheme: HTTPS only
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https') {
      return UrlPolicyResult.failure(
        UrlPolicyErrorCode.invalidScheme,
        'Only secure HTTPS URLs are allowed.',
      );
    }

    // Check userinfo
    if (uri.userInfo.isNotEmpty) {
      return UrlPolicyResult.failure(
        UrlPolicyErrorCode.userinfoNotAllowed,
        'URLs with user credentials are not allowed.',
      );
    }

    // Check port
    if (uri.hasPort && uri.port != 443) {
      return UrlPolicyResult.failure(
        UrlPolicyErrorCode.nonStandardPort,
        'Non-standard port (${uri.port}) is not permitted. Only standard HTTPS (443) is allowed.',
      );
    }

    // Check host
    final host = uri.host;
    if (host.isEmpty) {
      return UrlPolicyResult.failure(
        UrlPolicyErrorCode.emptyHost,
        'URL must contain a valid host.',
      );
    }

    // Check control characters in host
    for (int i = 0; i < host.length; i++) {
      final codeUnit = host.codeUnitAt(i);
      if (codeUnit < 32 || codeUnit == 127) {
        return UrlPolicyResult.failure(
          UrlPolicyErrorCode.invalidHost,
          'Host contains invalid control characters.',
        );
      }
    }

    // Check if host is an IP literal
    final ip = InternetAddress.tryParse(host);
    if (ip != null) {
      if (IpGuard.isBlocked(ip)) {
        return UrlPolicyResult.failure(
          UrlPolicyErrorCode.blockedIpLiteral,
          'Direct connections to private or reserved IP addresses are blocked.',
        );
      }
    }

    // Loopback names and the shorthand IPv4 spellings getaddrinfo accepts
    // ("2130706433", "0x7f.1", "127.1", "0177.0.0.1"): InternetAddress.tryParse
    // takes none of them, but the resolver would turn each into an address.
    // The resolved address is checked again (SafeHttpClient), this stops it
    // before any lookup.
    if (ip == null && (isLoopbackName(host) || looksLikeNumericIpv4(host))) {
      return UrlPolicyResult.failure(
        UrlPolicyErrorCode.blockedIpLiteral,
        'Direct connections to private or reserved IP addresses are blocked.',
      );
    }

    // Normalise URI: lowercase scheme and host, default 443 port stripped
    final normalized = Uri(
      scheme: 'https',
      host: host.toLowerCase(),
      port: (uri.hasPort && uri.port != 443) ? uri.port : null,
      path: uri.path.isEmpty ? '/' : uri.path,
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.hasFragment ? uri.fragment : null,
    );

    return UrlPolicyResult.success(normalized);
  }

  /// `localhost` and any name under `.localhost` (RFC 6761: always loopback).
  static bool isLoopbackName(String host) {
    var h = host.toLowerCase();
    if (h.endsWith('.')) h = h.substring(0, h.length - 1);
    return h == 'localhost' || h.endsWith('.localhost');
  }

  static final RegExp _numericLabel = RegExp(r'^(0x[0-9a-f]*|[0-9]+)$', caseSensitive: false);

  /// A host made only of decimal, octal or hex numbers (1 to 4 parts): an IPv4
  /// address in a shorthand spelling. No real domain looks like this (no
  /// top-level domain is numeric).
  static bool looksLikeNumericIpv4(String host) {
    var h = host;
    if (h.endsWith('.')) h = h.substring(0, h.length - 1);
    final parts = h.split('.');
    if (parts.isEmpty || parts.length > 4) return false;
    return parts.every((part) => part.isNotEmpty && _numericLabel.hasMatch(part));
  }
}
