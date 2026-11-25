// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
import 'dart:io';
import '../../domain/models/download_state.dart';

class IllegalDownloadStateTransitionException implements Exception {
  final DownloadTaskState from;
  final DownloadTaskState to;
  final String? reason;

  IllegalDownloadStateTransitionException(this.from, this.to, [this.reason]);

  @override
  String toString() =>
      'IllegalDownloadStateTransitionException: Cannot transition from ${from.name} to ${to.name}${reason != null ? " ($reason)" : ""}';
}

class DownloadStateMachine {
  static const Map<DownloadTaskState, Set<DownloadTaskState>> _allowedTransitions = {
    DownloadTaskState.queued: {
      DownloadTaskState.preparing,
      DownloadTaskState.paused,
      DownloadTaskState.cancelled,
      DownloadTaskState.failed,
    },
    DownloadTaskState.preparing: {
      DownloadTaskState.downloading,
      DownloadTaskState.paused,
      DownloadTaskState.cancelled,
      DownloadTaskState.failed,
    },
    DownloadTaskState.downloading: {
      DownloadTaskState.finalizing,
      DownloadTaskState.paused,
      DownloadTaskState.cancelled,
      DownloadTaskState.failed,
    },
    DownloadTaskState.paused: {
      DownloadTaskState.queued,
      DownloadTaskState.cancelled,
      DownloadTaskState.failed,
    },
    DownloadTaskState.finalizing: {
      DownloadTaskState.completed,
      DownloadTaskState.failed,
      DownloadTaskState.cancelled,
    },
    DownloadTaskState.completed: {},
    DownloadTaskState.cancelled: {},
    DownloadTaskState.failed: {
      DownloadTaskState.queued, // retry allowed
    },
  };

  /// Validates transition and returns the target state if legal, throws otherwise.
  static DownloadTaskState transition({
    required DownloadTaskState from,
    required DownloadTaskState to,
  }) {
    if (from == to) return to;

    final allowed = _allowedTransitions[from] ?? {};
    if (!allowed.contains(to)) {
      throw IllegalDownloadStateTransitionException(from, to);
    }
    return to;
  }

  /// On app start, any task stuck in preparing/downloading/finalizing becomes:
  /// - `paused` if the .part file exists and its size >= receivedBytes (or receivedBytes == 0)
  /// - `failed` if the .part file is missing or shorter than receivedBytes
  static DownloadTaskState reconcileStartupState({
    required DownloadTaskState currentState,
    required String? partFilePath,
    required int receivedBytes,
  }) {
    switch (currentState) {
      case DownloadTaskState.preparing:
      case DownloadTaskState.downloading:
      case DownloadTaskState.finalizing:
        if (receivedBytes > 0) {
          if (partFilePath == null) return DownloadTaskState.failed;
          final file = File(partFilePath);
          if (!file.existsSync() || file.lengthSync() < receivedBytes) {
            return DownloadTaskState.failed;
          }
        }
        return DownloadTaskState.paused;
      default:
        return currentState;
    }
  }
}

