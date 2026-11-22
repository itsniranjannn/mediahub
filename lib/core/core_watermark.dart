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

    final token = '$name:MediaHub:MasterAuthor';
    final hashToken = sha256.convert(utf8.encode(token)).toString();
    return hashToken == _expectedMasterTokenSha;
  }
}
