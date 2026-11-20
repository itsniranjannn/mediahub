import '../core/utils/formatters.dart';
import 'extractor_backend.dart';

/// One selectable download option shown in the format sheet.
class FormatChoice {
  final String id;

  /// Short headline, e.g. "1080p" or "MP3".
  final String label;

  /// Secondary line, e.g. "MP4 · ~85 MB".
  final String subtitle;
  final bool isAudio;

  /// yt-dlp `-f` selector.
  final String selector;

  /// When set, yt-dlp extracts/converts audio to this container (mp3, m4a ...).
  final String? audioFormat;
  final int? estimatedBytes;

  /// Expected size of each stream yt-dlp will download (video, audio). Used to
  /// merge the per-stream percentages into one overall progress value.
  final List<int> streamSizes;

  /// Stored on the download row and shown as a chip.
  final String qualityLabel;

  const FormatChoice({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.isAudio,
    required this.selector,
    required this.qualityLabel,
    this.audioFormat,
    this.estimatedBytes,
    this.streamSizes = const [],
  });
}

/// Builds download options from the formats yt-dlp actually reported, so the
/// user can see (and pick) every available quality instead of three canned presets.
class FormatOptions {
  FormatOptions._();

  // --- yt-dlp format selectors --------------------------------------------
  //
  // Every selector ends with yt-dlp's own catch-all, so a download that cannot
  // get the exact quality saves the nearest one instead of failing with
  // "Requested format is not available" (YouTube hands some of its clients
  // fewer formats than the quality list was read from). The format sort
  // ([formatSortFor]) keeps the chosen height as the cap for the catch-all
  // too, and prefers H.264 video with AAC (M4A) sound, which merge into an
  // MP4 that plays everywhere.

  /// Video and sound together; yt-dlp's default selector.
  static const String anyVideoSelector = 'bv*+ba/b';

  /// Sound only (or, when a site has no such stream, the best file there is).
  static const String audioSelector = 'ba/b';

  /// "Original audio" of the kind the quality sheet names (e.g. M4A), else
  /// any sound, else the best file. yt-dlp's own pick for plain `ba` is often
  /// WebM/Opus even when the sheet said M4A (seen on YouTube).
  static String originalAudioSelector(String? ext) {
    final e = (ext ?? '').toLowerCase();
    if (!RegExp(r'^[a-z0-9]{2,5}$').hasMatch(e)) return audioSelector;
    return 'ba[ext=$e]/$audioSelector';
  }

  /// Best video at most [maxHeight] pixels high merged with the best sound,
  /// else the best file with both at most that high, else anything.
  /// Without [maxHeight]: the best there is.
  static String videoSelector(int? maxHeight) => maxHeight == null
      ? anyVideoSelector
      : 'bv*[height<=$maxHeight]+ba/b[height<=$maxHeight]/$anyVideoSelector';

  static final RegExp _heightCap = RegExp(r'height<=\??(\d{2,5})');

  /// The height cap in [selector] (`[height<=1080]` -> 1080), if any.
  static int? maxHeightOf(String? selector) {
    final m = _heightCap.firstMatch(selector ?? '');
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// True for a selector that asks for sound only.
  static bool isAudioSelector(String selector) {
    final s = selector.trim();
    return s.startsWith('ba') || s.startsWith('bestaudio') || s.startsWith('wa') || s.startsWith('worstaudio');
  }

  /// [selector] with the catch-all added when it has none, so downloads
  /// queued by older versions of the app (still in the list, or retried) also
  /// get the nearest quality instead of failing. [audio]: the download is
  /// audio only. Selectors that already end in a catch-all stay as they are.
  static String withCatchAll(String selector, {required bool audio}) {
    final s = selector.trim();
    if (s.isEmpty) return s;
    final last = s.split('/').last.trim();
    // "b" / "best" (with no filter) already takes whatever there is.
    if (last == 'b' || last == 'best') return s;
    return '$s/${audio ? audioSelector : anyVideoSelector}';
  }

  /// yt-dlp format sort (`-S`) for a download with [selector]: at most the
  /// selector's height (the nearest one when that is missing), H.264 before
  /// VP9 / AV1 at the same height, MP4 video and M4A sound first. Null for
  /// sound-only downloads ([audioFormat] set, or an audio selector), so the
  /// sound picked is the one the quality sheet showed.
  static String? formatSortFor(String? selector, {String? audioFormat}) {
    if (audioFormat != null && audioFormat.isNotEmpty) return null;
    final s = selector?.trim() ?? '';
    if (s.isEmpty || isAudioSelector(s)) return null;
    final cap = maxHeightOf(s);
    return '${cap == null ? 'res' : 'height:$cap'},vcodec:h264,ext:mp4:m4a';
  }

  static int sizeOf(ExtractorFormat f, int durationSec) {
    if (f.filesize > 0) return f.filesize;
    if (f.tbr > 0 && durationSec > 0) {
      // tbr is kbit/s -> bytes = kbit/s * 1000 / 8 * seconds
      return (f.tbr * 125 * durationSec).round();
    }
    return 0;
  }

  static String _approx(int bytes) => bytes > 0 ? '~${formatFileSize(bytes)}' : 'size unknown';

  static ExtractorFormat? bestAudio(List<ExtractorFormat> formats) {
    final audios = formats.where((f) => f.isAudioOnly).toList();
    if (audios.isEmpty) return null;
    audios.sort((a, b) {
      final ra = a.abr > 0 ? a.abr : a.tbr;
      final rb = b.abr > 0 ? b.abr : b.tbr;
      final c = rb.compareTo(ra);
      if (c != 0) return c;
      // Prefer m4a (AAC) when the bitrate is equal: best device compatibility.
      final ma = a.ext == 'm4a' ? 1 : 0;
      final mb = b.ext == 'm4a' ? 1 : 0;
      return mb.compareTo(ma);
    });
    return audios.first;
  }

  static ExtractorFormat? _bestVideoAt(List<ExtractorFormat> formats, int height) {
    final candidates = formats.where((f) => f.hasVideo && f.height == height).toList();
    if (candidates.isEmpty) return null;
    // Prefer video-only streams (they get merged with the best audio) with the highest bitrate.
    candidates.sort((a, b) {
      final ao = a.hasAudio ? 0 : 1;
      final bo = b.hasAudio ? 0 : 1;
      if (ao != bo) return bo.compareTo(ao);
      return b.tbr.compareTo(a.tbr);
    });
    return candidates.first;
  }

  /// The file a download at [height] ends up in: MP4 when an H.264 stream
  /// exists there (the format sort picks it), MKV when only VP9 does (YouTube
  /// above 1080p), otherwise MP4.
  static String containerAt(List<ExtractorFormat> formats, int height) {
    final codecs = formats.where((f) => f.hasVideo && f.height == height).map((f) => f.vcodec.toLowerCase());
    if (codecs.any((c) => c.startsWith('avc') || c.startsWith('h264'))) return 'MP4';
    if (codecs.any((c) => c.startsWith('vp'))) return 'MKV';
    return 'MP4';
  }

  static List<FormatChoice> build(ExtractorMetadata meta) {
    final formats = meta.formats;
    final duration = meta.durationSec;
    final audio = bestAudio(formats);
    final audioSize = audio == null ? 0 : sizeOf(audio, duration);

    final heights = formats
        .where((f) => f.hasVideo && f.height >= 144)
        .map((f) => f.height)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    final video = <FormatChoice>[];
    for (final h in heights.take(9)) {
      final v = _bestVideoAt(formats, h);
      if (v == null) continue;
      final vSize = sizeOf(v, duration);
      final needsAudio = !v.hasAudio;
      final total = vSize > 0 ? vSize + (needsAudio ? audioSize : 0) : 0;
      final fps = v.fps >= 50 ? ' ${v.fps.round()}fps' : '';
      final label = '${h}p$fps';
      video.add(FormatChoice(
        id: 'v$h',
        label: label,
        subtitle: '${containerAt(formats, h)} · ${_approx(total)}',
        isAudio: false,
        selector: videoSelector(h),
        qualityLabel: label,
        estimatedBytes: total > 0 ? total : null,
        streamSizes: [
          if (vSize > 0) vSize,
          if (needsAudio && audioSize > 0) audioSize,
        ],
      ));
    }

    final out = <FormatChoice>[];
    if (video.isNotEmpty) {
      final top = video.first;
      out.add(FormatChoice(
        id: 'best',
        label: 'Best available (${top.label})',
        subtitle: top.subtitle,
        isAudio: false,
        selector: anyVideoSelector,
        qualityLabel: top.qualityLabel,
        estimatedBytes: top.estimatedBytes,
        streamSizes: top.streamSizes,
      ));
      out.addAll(video);
    } else if (formats.isEmpty) {
      // Site returned no format list: fall back to yt-dlp's own "best".
      out.add(const FormatChoice(
        id: 'best',
        label: 'Best available',
        subtitle: 'MP4',
        isAudio: false,
        selector: anyVideoSelector,
        qualityLabel: 'Best',
      ));
    }

    // --- audio ---
    final audioLabel = audio == null
        ? 'Original audio'
        : 'Original audio (${audio.ext.toUpperCase()}${audio.abr > 0 ? ' ${audio.abr.round()} kbps' : ''})';
    out.add(FormatChoice(
      id: 'audio_best',
      label: audioLabel,
      subtitle: 'No conversion · ${_approx(audioSize)}',
      isAudio: true,
      selector: originalAudioSelector(audio?.ext),
      qualityLabel: audio != null && audio.abr > 0
          ? 'Audio ${audio.abr.round()} kbps'
          : 'Audio',
      estimatedBytes: audioSize > 0 ? audioSize : null,
      streamSizes: [if (audioSize > 0) audioSize],
    ));

    final mp3Bytes = duration > 0 ? duration * 32000 : 0; // ~256 kbit/s VBR
    out.add(FormatChoice(
      id: 'audio_mp3',
      label: 'MP3 (converted)',
      subtitle: 'Plays everywhere · ${_approx(mp3Bytes)}',
      isAudio: true,
      selector: audioSelector,
      audioFormat: 'mp3',
      qualityLabel: 'MP3',
      estimatedBytes: mp3Bytes > 0 ? mp3Bytes : null,
      streamSizes: [if (audioSize > 0) audioSize],
    ));

    return out;
  }
}
