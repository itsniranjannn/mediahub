// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
/// Text folding for the library search (Music tab, playlists, albums).
///
/// Both what is stored ([librarySearchKey], the `search_key` column) and what
/// the user types ([searchTerms]) go through [foldForSearch], so a match only
/// needs a plain substring test:
/// - lowercased with Dart's `toLowerCase` ("ÉTÉ" and "été" are the same);
/// - Latin letters lose their accents, as after Unicode NFD with the
///   combining marks dropped ("Beyoncé" matches "beyonce");
/// - Devanagari is left intact: its vowel signs and virama are part of the
///   word, so "नेपा" still matches "नेपाली". Only its precomposed nukta
///   letters are split the NFD way (क़ is क + ़), so either spelling matches;
///   chandrabindu is folded to anusvara, as people type either ("साँझ" and
///   "सांझ" are the same word), and Devanagari digits become ASCII digits
///   ("गीत २" and "गीत 2");
/// - zero-width joiners and spaces are dropped and whitespace runs become one
///   space;
/// - curly and other typographic quotes become the plain ' and " (the
///   iPhone keyboard types ’ for an apostrophe, so "don’t" and "don't" are
///   the same), and typographic dashes become a plain - ("A – B" and "A - B").
///
/// Romanised search: "resham" finds "रेशम फिरिरी", as Nepali is very often
/// typed in Latin letters. Devanagari fields are transliterated and both
/// sides are reduced to a loose [romanSkeleton] ("aa", "a" and the inherent
/// vowel dropped, sh = s, ph = f, ee = i, oo = u, v = w = b, doubled letters
/// once), which absorbs the usual spelling differences ("geet" / "git",
/// "sapana" / "sapna", "phool" / "fool"). The stored skeleton is written in
/// private-use letters ([romanSearchField]), so a Latin word can only meet it
/// through [romanTermPattern], never match an English title by accident.
///
/// Dart has no built-in normaliser and the app takes no extra dependency for
/// it, so the decomposition is a table of the precomposed Latin letters
/// (Latin-1, Latin Extended-A/B and Vietnamese).
library;

/// Separates the fields inside a search key. A search term never contains it
/// (terms are split on whitespace), so a term cannot match across two fields.
const String searchKeyFieldSeparator = '\n';

/// Ends every stored key made by the current [foldForSearch] rules (a
/// private-use character, which [foldForSearch] drops from what is typed, so
/// no search term can match it). Bump it when the folding changes: keys
/// without it are rebuilt before the next search or scan. U+E004 since
/// typographic quotes and dashes fold to plain ones.
const String searchKeyVersionTag = '';

/// Whether [key] was made by the current folding rules.
bool isCurrentSearchKey(String? key) => key != null && key.endsWith(searchKeyVersionTag);

/// [text] folded for matching: see the library comment.
String foldForSearch(String text) {
  if (text.isEmpty) return text;
  final lower = text.toLowerCase();
  final out = StringBuffer();
  var lastWasSpace = false;
  for (final rune in lower.runes) {
    if (_isCombiningMark(rune) || _isZeroWidth(rune) || _isPrivateUse(rune)) continue;
    if (_isSpace(rune)) {
      if (!lastWasSpace) out.write(' ');
      lastWasSpace = true;
      continue;
    }
    lastWasSpace = false;
    final nukta = _devanagariNukta[rune];
    if (nukta != null) {
      out.writeCharCode(nukta);
      out.writeCharCode(0x093C);
      continue;
    }
    if (rune == 0x0901) {
      out.writeCharCode(0x0902); // chandrabindu as anusvara
      continue;
    }
    if (rune >= 0x0966 && rune <= 0x096F) {
      out.writeCharCode(0x30 + rune - 0x0966); // Devanagari digit as ASCII
      continue;
    }
    final punctuation = _plainPunctuation[rune];
    if (punctuation != null) {
      out.writeCharCode(punctuation);
      continue;
    }
    final base = _latinBase[rune];
    if (base != null) {
      out.write(base);
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString().trim();
}

/// The stored search key of a song or video: its title, artist, album and
/// album artist, each folded, one per line; then the [romanSearchField] of
/// each one written in Devanagari; then [searchKeyVersionTag].
String librarySearchKey({
  required String title,
  String? artist,
  String? album,
  String? albumArtist,
}) {
  final fields = [
    title,
    artist ?? '',
    album ?? '',
    if (albumArtist != null && albumArtist.isNotEmpty && albumArtist != artist) albumArtist,
  ].map(foldForSearch).toList();
  return [
    ...fields,
    for (final f in fields) ?romanSearchField(f),
    searchKeyVersionTag,
  ].join(searchKeyFieldSeparator);
}

/// The loose Latin spelling of [text] for romanised search (see the library
/// comment): lowercase Latin letters and spaces only.
String romanSkeleton(String text) {
  var s = text.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), '');
  for (final (from, to) in const [
    ('chh', 'ch'),
    ('ph', 'f'),
    ('sh', 's'),
    ('ee', 'i'),
    ('oo', 'u'),
    ('v', 'b'),
    ('w', 'b'),
    ('z', 'j'),
    ('q', 'k'),
    ('x', 'ks'),
    ('a', ''),
  ]) {
    s = s.replaceAll(from, to);
  }
  // Doubled letters once ("pyaar", "Krishnna"), whitespace runs as one space.
  return s.replaceAllMapped(RegExp(r'([a-z])\1+'), (m) => m[1]!).replaceAll(RegExp(r' +'), ' ').trim();
}

/// The [romanSkeleton] of a folded field that has Devanagari in it, written
/// in private-use letters for the stored key; null for other fields.
String? romanSearchField(String folded) {
  if (!folded.runes.any(_isDevanagari)) return null;
  final skeleton = romanSkeleton(transliterateDevanagari(folded));
  return skeleton.isEmpty ? null : _privateLetters(skeleton);
}

/// What a typed Latin word looks for among the [romanSearchField]s: its
/// [romanSkeleton] in private-use letters. Null for words that are not plain
/// Latin letters, or too short to mean anything once loosened (fewer than two
/// letters left), so "a" or "ma" only search the titles as written.
String? romanTermPattern(String term) {
  if (!RegExp(r'^[a-z]+$').hasMatch(term)) return null;
  final skeleton = romanSkeleton(term);
  return skeleton.length < 2 ? null : _privateLetters(skeleton);
}

/// [folded] Devanagari in plain Latin letters (a common Nepali romanisation;
/// other characters are kept). Exactness does not matter: [romanSkeleton]
/// loosens both sides.
String transliterateDevanagari(String folded) {
  final out = StringBuffer();
  for (final rune in folded.runes) {
    final consonant = _devanagariConsonants[rune];
    if (consonant != null) {
      out.write(consonant); // the inherent vowel is dropped by the skeleton anyway
      continue;
    }
    final vowel = _devanagariVowels[rune];
    if (vowel != null) {
      out.write(vowel);
      continue;
    }
    if (rune == 0x0902 || rune == 0x0901) {
      out.write('n'); // anusvara, chandrabindu
    } else if (rune == 0x0903) {
      out.write('h'); // visarga
    } else if (rune == 0x0964 || rune == 0x0965) {
      out.write(' '); // danda
    } else if (rune == 0x093C || rune == 0x094D || rune == 0x093D) {
      // nukta, virama, avagraha: nothing to write
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

String _privateLetters(String skeleton) =>
    String.fromCharCodes([for (final c in skeleton.codeUnits) c == 0x20 ? 0x20 : 0xE100 + c]);

bool _isDevanagari(int r) => r >= 0x0900 && r <= 0x097F;

const Map<int, String> _devanagariConsonants = {
  0x0915: 'k', 0x0916: 'kh', 0x0917: 'g', 0x0918: 'gh', 0x0919: 'ng', //
  0x091A: 'ch', 0x091B: 'chh', 0x091C: 'j', 0x091D: 'jh', 0x091E: 'ny', //
  0x091F: 't', 0x0920: 'th', 0x0921: 'd', 0x0922: 'dh', 0x0923: 'n', //
  0x0924: 't', 0x0925: 'th', 0x0926: 'd', 0x0927: 'dh', 0x0928: 'n', //
  0x092A: 'p', 0x092B: 'ph', 0x092C: 'b', 0x092D: 'bh', 0x092E: 'm', //
  0x092F: 'y', 0x0930: 'r', 0x0932: 'l', 0x0933: 'l', 0x0935: 'w', //
  0x0936: 'sh', 0x0937: 'sh', 0x0938: 's', 0x0939: 'h',
};

/// Independent vowels and vowel signs.
const Map<int, String> _devanagariVowels = {
  0x0905: 'a', 0x0906: 'aa', 0x0907: 'i', 0x0908: 'i', 0x0909: 'u', 0x090A: 'u', //
  0x090B: 'ri', 0x090F: 'e', 0x0910: 'ai', 0x0913: 'o', 0x0914: 'au', 0x0911: 'o', //
  0x093E: 'aa', 0x093F: 'i', 0x0940: 'i', 0x0941: 'u', 0x0942: 'u', 0x0943: 'ri', //
  0x0947: 'e', 0x0948: 'ai', 0x094B: 'o', 0x094C: 'au', 0x0945: 'e', 0x0949: 'o',
};

/// The words of [query], folded; empty when there is nothing to search for.
/// Every word has to match (in the title, artist or album).
List<String> searchTerms(String? query) {
  if (query == null) return const [];
  final folded = foldForSearch(query);
  if (folded.isEmpty) return const [];
  return folded.split(' ').where((w) => w.isNotEmpty).toList();
}

/// The `LIKE` pattern that finds [term] anywhere, with `%`, `_` and the escape
/// character itself escaped (use with `ESCAPE '\'`).
String likeContainsPattern(String term) {
  final escaped = term.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}');
  return '%$escaped%';
}

/// Whether every one of [terms] is in one of [fields] (each already folded),
/// as written or, for a Latin word, romanised ([romanTermPattern]).
bool matchesAllTerms(List<String> terms, Iterable<String> fields) {
  if (terms.isEmpty) return true;
  final folded = fields.toList();
  List<String>? roman;
  for (final term in terms) {
    if (folded.any((f) => f.contains(term))) continue;
    final pattern = romanTermPattern(term);
    if (pattern == null) return false;
    roman ??= [for (final f in folded) ?romanSearchField(f)];
    if (!roman.any((f) => f.contains(pattern))) return false;
  }
  return true;
}

bool _isCombiningMark(int r) =>
    (r >= 0x0300 && r <= 0x036F) ||
    (r >= 0x1AB0 && r <= 0x1AFF) ||
    (r >= 0x1DC0 && r <= 0x1DFF) ||
    (r >= 0x20D0 && r <= 0x20FF) ||
    (r >= 0xFE20 && r <= 0xFE2F);

bool _isPrivateUse(int r) => r >= 0xE000 && r <= 0xF8FF;

bool _isZeroWidth(int r) => r == 0x200B || r == 0x200C || r == 0x200D || r == 0x2060 || r == 0xFEFF;

bool _isSpace(int r) =>
    r == 0x20 || r == 0x09 || r == 0x0A || r == 0x0D || r == 0xA0 || r == 0x3000 || (r >= 0x2000 && r <= 0x200A);

/// Typographic quotes and dashes and the plain ASCII character they stand
/// for. Phone keyboards type the curly ones ("smart punctuation" on iPhone),
/// titles from the web often have them, and people type either.
const Map<int, int> _plainPunctuation = {
  // Apostrophes and single quotes as '.
  0x2018: 0x27, // ‘ left single quote
  0x2019: 0x27, // ’ right single quote (the iPhone apostrophe)
  0x201A: 0x27, // ‚ single low-9 quote
  0x201B: 0x27, // ‛ single high-reversed-9 quote
  0x2032: 0x27, // ′ prime
  0x2039: 0x27, // ‹ single angle quote
  0x203A: 0x27, // › single angle quote
  0x02BC: 0x27, // ʼ modifier letter apostrophe
  0x0060: 0x27, // ` grave accent, typed for an apostrophe
  0x00B4: 0x27, // ´ acute accent, typed for an apostrophe
  0xFF07: 0x27, // ＇ fullwidth apostrophe
  // Double quotes as ".
  0x201C: 0x22, // “ left double quote
  0x201D: 0x22, // ” right double quote
  0x201E: 0x22, // „ double low-9 quote
  0x201F: 0x22, // ‟ double high-reversed-9 quote
  0x2033: 0x22, // ″ double prime
  0x00AB: 0x22, // « left guillemet
  0x00BB: 0x22, // » right guillemet
  0xFF02: 0x22, // ＂ fullwidth quote
  // Dashes as -.
  0x2010: 0x2D, // ‐ hyphen
  0x2011: 0x2D, // ‑ non-breaking hyphen
  0x2012: 0x2D, // ‒ figure dash
  0x2013: 0x2D, // – en dash
  0x2014: 0x2D, // — em dash (the iPhone's "smart dash")
  0x2015: 0x2D, // ― horizontal bar
  0x2212: 0x2D, // − minus sign
  0xFE58: 0x2D, // ﹘ small em dash
  0xFE63: 0x2D, // ﹣ small hyphen-minus
  0xFF0D: 0x2D, // － fullwidth hyphen-minus
};

/// Precomposed Devanagari nukta letters and their base (NFD splits them).
const Map<int, int> _devanagariNukta = {
  0x0929: 0x0928, // ऩ
  0x0931: 0x0930, // ऱ
  0x0934: 0x0933, // ऴ
  0x0958: 0x0915, // क़
  0x0959: 0x0916, // ख़
  0x095A: 0x0917, // ग़
  0x095B: 0x091C, // ज़
  0x095C: 0x0921, // ड़
  0x095D: 0x0922, // ढ़
  0x095E: 0x092B, // फ़
  0x095F: 0x092F, // य़
};

/// Lowercase precomposed Latin letters and the base letter NFD leaves after
/// its marks are dropped. A few letters without a decomposition (ø, đ, ł, ħ,
/// ı) are folded too, as users type them without the stroke.
final Map<int, String> _latinBase = _buildLatinBase();

Map<int, String> _buildLatinBase() {
  const groups = <String, String>{
    'a': 'àáâãäåāăąǎǟǡǻȁȃȧạảấầẩẫậắằẳẵặ',
    'c': 'çćĉċč',
    'd': 'ďđḍḏ',
    'e': 'èéêëēĕėęěȅȇȩẹẻẽếềểễệ',
    'g': 'ĝğġģǧǵ',
    'h': 'ĥħḥḫ',
    'i': 'ìíîïĩīĭįıǐȉȋịỉ',
    'j': 'ĵǰ',
    'k': 'ķǩ',
    'l': 'ĺļľŀłḷ',
    'm': 'ḿṁṃ',
    'n': 'ñńņňǹṅṇ',
    'o': 'òóôõöøōŏőơǒǫǭǿȍȏȫȭȯȱọỏốồổỗộớờởỡợ',
    'r': 'ŕŗřȑȓṛ',
    's': 'śŝşšșṣ',
    't': 'ţťŧțṭ',
    'u': 'ùúûüũūŭůűųưǔǖǘǚǜȕȗụủứừửữự',
    'w': 'ŵẁẃẅ',
    'y': 'ýÿŷȳẏỳỵỷỹ',
    'z': 'źżžẓ',
  };
  final map = <int, String>{};
  groups.forEach((base, letters) {
    for (final rune in letters.runes) {
      map[rune] = base;
    }
  });
  return map;
}
