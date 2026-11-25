// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
enum DownloadTaskState {
  queued,
  preparing,
  downloading,
  paused,
  finalizing,
  completed,
  cancelled,
  failed,
}

