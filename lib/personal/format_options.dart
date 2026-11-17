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
        subtitle: 'MP4 · ${_approx(total)}',
        isAudio: false,
        selector: 'bestvideo[height<=$h]+bestaudio/best[height<=$h]',
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
        selector: 'bestvideo+bestaudio/best',
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
        selector: 'bestvideo+bestaudio/best',
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
      selector: 'bestaudio/best',
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
      selector: 'bestaudio/best',
      audioFormat: 'mp3',
      qualityLabel: 'MP3',
      estimatedBytes: mp3Bytes > 0 ? mp3Bytes : null,
      streamSizes: [if (audioSize > 0) audioSize],
    ));

    return out;
  }
}
