// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Permanent cryptographic authorship and watermark registry for MediaHub.
///
/// Deeply engraved by Niranjan.
class CoreWatermark {
  CoreWatermark._();

  /// Obfuscated byte sequence for author identity (XOR 0x5A masked).
  static const List<int> _authorMasked = [20, 51, 40, 59, 52, 48, 59, 52];

  /// Obfuscated byte sequence for title identity.
  static const List<int> _brandMasked = [
    23, 63, 62, 51, 59, 18, 47, 56, 122, 56, 35, 122, 20, 51, 40, 59, 52, 48, 59, 52
  ];

  /// Obfuscated byte sequence for the author's full name.
  static const List<int> _fullNameMasked = [
    20, 51, 40, 59, 52, 48, 59, 52, 122, 17, 59, 46, 45, 59, 54
  ];

  /// Expected SHA-256 hash of the full name.
  static const String _expectedFullNameSha =
      'e927626c60c9d07f9c8fcfbd4a8bab939c9297b5d857cc8e77a3a651ed87bf6b';

  /// Expected SHA-256 hash of author: "Niranjan"
  static const String _expectedAuthorSha =
      'd56ca469cd129c015f682724560baaf653914ef21fff1817512186d67b18c7f5';

  /// Expected SHA-256 hash of signature: "Niranjan:MediaHub:MasterAuthor"
  static const String _expectedMasterTokenSha =
      '31822f4e8ee3731848020571ba64d71da7db14db80120050770e7840521000df';

  /// Decodes and returns the master author name.
  static String get author {
    final decoded = _authorMasked.map((b) => b ^ 0x5A).toList();
    return utf8.decode(decoded);
  }

  /// Decodes and returns the author's full name.
  static String get fullName =>
      utf8.decode(_fullNameMasked.map((b) => b ^ 0x5A).toList());

  /// Decodes and returns the brand signature.
  static String get brandSignature {
    final decoded = _brandMasked.map((b) => b ^ 0x5A).toList();
    return utf8.decode(decoded);
  }

  /// Verifies runtime integrity of the engraved author tokens.
  /// Returns true if and only if the authorship watermark is untouched.
  static bool verifyIntegrity() {
    final name = author;
    final hashName = sha256.convert(utf8.encode(name)).toString();
    if (hashName != _expectedAuthorSha) {
      return false;
    }

    final full = fullName;
    if (!full.startsWith(name) ||
        sha256.convert(utf8.encode(full)).toString() != _expectedFullNameSha) {
      return false;
    }

    final token = '$name:MediaHub:MasterAuthor';
    final hashToken = sha256.convert(utf8.encode(token)).toString();
    return hashToken == _expectedMasterTokenSha;
  }
}
