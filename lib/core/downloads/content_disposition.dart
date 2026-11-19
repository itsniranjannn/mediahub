import 'dart:convert';

/// The file name a server gives in a `Content-Disposition` header.
///
/// Handles what real download servers send (RFC 6266 and common mistakes):
/// - `filename*=UTF-8''Na%C3%AFve%20song.mp3` (wins over a plain `filename`),
///   also in ISO-8859-1;
/// - `filename="Don't stop; live.mp3"` (quotes, apostrophes, semicolons and
///   `\"` escapes inside the quotes);
/// - `filename=song.mp3` without quotes;
/// - a percent-encoded plain name (`filename="My%20song.mp3"`), decoded only
///   when it decodes cleanly: "100% hits.mp3" stays as it is and never
///   throws.
///
/// The result is not sanitized: pass it through `SafeFilename.sanitize`.
class ContentDisposition {
  ContentDisposition._();

  /// The file name in [header], or null when there is none.
  static String? fileName(String? header) {
    if (header == null || header.trim().isEmpty) return null;
    final params = _params(header);
    final extended = params['filename*'];
    if (extended != null) {
      final decoded = _decodeExtended(extended);
      if (decoded != null && decoded.trim().isNotEmpty) return decoded.trim();
    }
    final plain = params['filename'];
    if (plain == null || plain.trim().isEmpty) return null;
    return _maybePercentDecoded(plain.trim());
  }

  /// `name=value` pairs after the disposition type, names in lower case.
  static Map<String, String> _params(String header) {
    final out = <String, String>{};
    var i = header.indexOf(';');
    if (i < 0) {
      // Some servers send only `filename=...` with no type in front.
      if (!header.contains('=')) return out;
      i = -1;
    }
    final s = header;
    while (i < s.length) {
      i++; // past ';' (or to 0)
      while (i < s.length && (s[i] == ' ' || s[i] == '\t' || s[i] == ';')) {
        i++;
      }
      final eq = s.indexOf('=', i);
      if (eq < 0) break;
      final name = s.substring(i, eq).trim().toLowerCase();
      var j = eq + 1;
      while (j < s.length && (s[j] == ' ' || s[j] == '\t')) {
        j++;
      }
      String value;
      if (j < s.length && s[j] == '"') {
        final buf = StringBuffer();
        j++;
        while (j < s.length && s[j] != '"') {
          if (s[j] == r'\' && j + 1 < s.length) j++;
          buf.write(s[j]);
          j++;
        }
        value = buf.toString();
        // Past the closing quote, up to the next ';'.
        final next = s.indexOf(';', j);
        i = next < 0 ? s.length : next;
      } else {
        final next = s.indexOf(';', j);
        value = s.substring(j, next < 0 ? s.length : next).trim();
        // Single quotes some servers put around the name.
        if (value.length >= 2 && value.startsWith("'") && value.endsWith("'") && !name.endsWith('*')) {
          value = value.substring(1, value.length - 1);
        }
        i = next < 0 ? s.length : next;
      }
      if (name.isNotEmpty) out.putIfAbsent(name, () => value);
    }
    return out;
  }

  /// `charset'language'percent-encoded` (RFC 5987).
  static String? _decodeExtended(String value) {
    final first = value.indexOf("'");
    final second = first < 0 ? -1 : value.indexOf("'", first + 1);
    if (second < 0) return _maybePercentDecoded(value);
    final charset = value.substring(0, first).trim().toLowerCase();
    final encoded = value.substring(second + 1);
    final bytes = _percentBytes(encoded);
    if (bytes == null) return null;
    try {
      if (charset == 'iso-8859-1' || charset == 'latin1') return latin1.decode(bytes);
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  static String _maybePercentDecoded(String value) {
    if (!value.contains('%')) return value;
    final bytes = _percentBytes(value);
    if (bytes == null) return value;
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return value;
    }
  }

  /// The bytes of a percent-encoded [s], or null when any '%' is not
  /// followed by two hex digits.
  static List<int>? _percentBytes(String s) {
    final out = <int>[];
    final raw = utf8.encode(s);
    for (var i = 0; i < raw.length; i++) {
      final c = raw[i];
      if (c == 0x25) {
        if (i + 2 >= raw.length) return null;
        final hex = String.fromCharCodes(raw.sublist(i + 1, i + 3));
        final v = int.tryParse(hex, radix: 16);
        if (v == null) return null;
        out.add(v);
        i += 2;
      } else {
        out.add(c);
      }
    }
    return out;
  }
}
