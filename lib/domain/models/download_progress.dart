class DownloadProgressUpdate {
  final String id;
  final int receivedBytes;
  final int? totalBytes;
  final double? progress;
  final double? speedBytesPerSec;
  final Duration? eta;

  const DownloadProgressUpdate({
    required this.id,
    required this.receivedBytes,
    this.totalBytes,
    this.progress,
    this.speedBytesPerSec,
    this.eta,
  });
}

