import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/downloads/download_state_machine.dart';
import 'package:mediahub/domain/models/download_state.dart';

void main() {
  group('PART 2: DownloadStateMachine Transitions', () {
    test('Legal transitions execute successfully', () {
      // queued -> preparing -> downloading -> finalizing -> completed
      expect(DownloadStateMachine.transition(from: DownloadTaskState.queued, to: DownloadTaskState.preparing), DownloadTaskState.preparing);
      expect(DownloadStateMachine.transition(from: DownloadTaskState.preparing, to: DownloadTaskState.downloading), DownloadTaskState.downloading);
      expect(DownloadStateMachine.transition(from: DownloadTaskState.downloading, to: DownloadTaskState.finalizing), DownloadTaskState.finalizing);
      expect(DownloadStateMachine.transition(from: DownloadTaskState.finalizing, to: DownloadTaskState.completed), DownloadTaskState.completed);

      // downloading -> paused -> queued
      expect(DownloadStateMachine.transition(from: DownloadTaskState.downloading, to: DownloadTaskState.paused), DownloadTaskState.paused);
      expect(DownloadStateMachine.transition(from: DownloadTaskState.paused, to: DownloadTaskState.queued), DownloadTaskState.queued);

      // cancellations
      expect(DownloadStateMachine.transition(from: DownloadTaskState.queued, to: DownloadTaskState.cancelled), DownloadTaskState.cancelled);
      expect(DownloadStateMachine.transition(from: DownloadTaskState.downloading, to: DownloadTaskState.cancelled), DownloadTaskState.cancelled);
      expect(DownloadStateMachine.transition(from: DownloadTaskState.paused, to: DownloadTaskState.cancelled), DownloadTaskState.cancelled);

      // failures & retry
      expect(DownloadStateMachine.transition(from: DownloadTaskState.downloading, to: DownloadTaskState.failed), DownloadTaskState.failed);
      expect(DownloadStateMachine.transition(from: DownloadTaskState.failed, to: DownloadTaskState.queued), DownloadTaskState.queued);
    });

    test('Illegal transitions throw IllegalDownloadStateTransitionException', () {
      // completed is terminal
      expect(
        () => DownloadStateMachine.transition(from: DownloadTaskState.completed, to: DownloadTaskState.downloading),
        throwsA(isA<IllegalDownloadStateTransitionException>()),
      );
      expect(
        () => DownloadStateMachine.transition(from: DownloadTaskState.completed, to: DownloadTaskState.queued),
        throwsA(isA<IllegalDownloadStateTransitionException>()),
      );

      // cancelled is terminal
      expect(
        () => DownloadStateMachine.transition(from: DownloadTaskState.cancelled, to: DownloadTaskState.downloading),
        throwsA(isA<IllegalDownloadStateTransitionException>()),
      );

      // queued cannot jump straight to completed or finalizing
      expect(
        () => DownloadStateMachine.transition(from: DownloadTaskState.queued, to: DownloadTaskState.completed),
        throwsA(isA<IllegalDownloadStateTransitionException>()),
      );
      expect(
        () => DownloadStateMachine.transition(from: DownloadTaskState.queued, to: DownloadTaskState.finalizing),
        throwsA(isA<IllegalDownloadStateTransitionException>()),
      );
    });

    test('Reconcile startup state: stuck tasks become paused or failed', () async {
      final tempDir = await Directory.systemTemp.createTemp('state_reconcile_test');
      final validPart = File('${tempDir.path}/valid.part');
      await validPart.writeAsBytes(List.filled(1000, 1));

      final truncatedPart = File('${tempDir.path}/truncated.part');
      await truncatedPart.writeAsBytes(List.filled(500, 1));

      // 1. Stuck in downloading with intact .part file -> paused
      final state1 = DownloadStateMachine.reconcileStartupState(
        currentState: DownloadTaskState.downloading,
        partFilePath: validPart.path,
        receivedBytes: 1000,
      );
      expect(state1, DownloadTaskState.paused);

      // 2. Stuck in finalizing with intact .part file -> paused
      final state2 = DownloadStateMachine.reconcileStartupState(
        currentState: DownloadTaskState.finalizing,
        partFilePath: validPart.path,
        receivedBytes: 1000,
      );
      expect(state2, DownloadTaskState.paused);

      // 3. Stuck with missing file -> failed
      final state3 = DownloadStateMachine.reconcileStartupState(
        currentState: DownloadTaskState.downloading,
        partFilePath: '${tempDir.path}/missing.part',
        receivedBytes: 1000,
      );
      expect(state3, DownloadTaskState.failed);

      // 4. Stuck with truncated file (smaller than receivedBytes) -> failed
      final state4 = DownloadStateMachine.reconcileStartupState(
        currentState: DownloadTaskState.downloading,
        partFilePath: truncatedPart.path,
        receivedBytes: 1000,
      );
      expect(state4, DownloadTaskState.failed);

      // 5. Already completed or failed remains unchanged
      expect(
        DownloadStateMachine.reconcileStartupState(
          currentState: DownloadTaskState.completed,
          partFilePath: null,
          receivedBytes: 1000,
        ),
        DownloadTaskState.completed,
      );
      expect(
        DownloadStateMachine.reconcileStartupState(
          currentState: DownloadTaskState.failed,
          partFilePath: null,
          receivedBytes: 1000,
        ),
        DownloadTaskState.failed,
      );

      await tempDir.delete(recursive: true);
    });
  });
}

