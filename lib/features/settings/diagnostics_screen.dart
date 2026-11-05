import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/logging/diagnostics_service.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _copyLogs(List<String> logs) {
    Clipboard.setData(ClipboardData(text: logs.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diagnostics logs copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _clearLogs() async {
    await DiagnosticsService.instance.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Diagnostics logs cleared'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Formats log lines cleanly and null-safely:
  /// e.g. "[12:34:56] service_start" or "[12:34:56] play {\"caller\":\"in_app\"}"
  Widget _buildLogItem(String? rawLine) {
    if (rawLine == null || rawLine.isEmpty) {
      return const SizedBox.shrink();
    }

    // Safely extract timestamp and event name
    String timestamp = '';
    String eventName = rawLine;
    String? jsonPayload;

    final closeBracket = rawLine.indexOf(']');
    if (rawLine.startsWith('[') && closeBracket != -1) {
      timestamp = rawLine.substring(1, closeBracket);
      final remainder = rawLine.substring(closeBracket + 1).trim();
      final spaceIdx = remainder.indexOf(' ');
      if (spaceIdx != -1) {
        eventName = remainder.substring(0, spaceIdx);
        jsonPayload = remainder.substring(spaceIdx + 1).trim();
      } else {
        eventName = remainder;
      }
    }

    Map<String, dynamic>? dataMap;
    if (jsonPayload != null && jsonPayload.startsWith('{') && jsonPayload.endsWith('}')) {
      try {
        final decoded = jsonDecode(jsonPayload);
        if (decoded is Map<String, dynamic>) {
          dataMap = decoded;
        }
      } catch (_) {
        // Fall back gracefully to displaying the raw payload
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (timestamp.isNotEmpty) ...[
                Text(
                  timestamp,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm8),
              ],
              Text(
                eventName,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          if (dataMap != null && dataMap.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12.0, top: 2.0),
              child: Text(
                dataMap.entries.map((e) => '${e.key}: ${e.value}').join(', '),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else if (jsonPayload != null && jsonPayload.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12.0, top: 2.0),
              child: Text(
                jsonPayload,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics Log'),
        actions: [
          ValueListenableBuilder<List<String>>(
            valueListenable: DiagnosticsService.instance.logsNotifier,
            builder: (context, logs, _) {
              return IconButton(
                icon: const Icon(Icons.copy_rounded),
                tooltip: 'Copy logs',
                onPressed: logs.isEmpty ? null : () => _copyLogs(logs),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Clear logs',
            onPressed: _clearLogs,
          ),
        ],
      ),
      body: ValueListenableBuilder<List<String>>(
        valueListenable: DiagnosticsService.instance.logsNotifier,
        builder: (context, logs, _) {
          if (logs.isEmpty) {
            return const Center(
              child: Text(
                'No diagnostic logs recorded yet.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            );
          }

          return SelectionArea(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(AppSpacing.md12),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                return _buildLogItem(logs[index]);
              },
            ),
          );
        },
      ),
    );
  }
}
