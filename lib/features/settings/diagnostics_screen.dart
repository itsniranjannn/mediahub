import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/logging/diagnostics_service.dart';
import '../../shared/widgets/ui_kit.dart';

/// Monospace look for log text; falls back to the iOS system monospace fonts.
const List<String> _monoFallback = ['Menlo', 'Courier New', 'Courier'];

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final ScrollController _scrollController = ScrollController();

  /// Parsed lines, keyed by the raw text, so a line is decoded once rather
  /// than on every rebuild. Bounded by [DiagnosticsService.maxLines].
  final Map<String, _LogEntry> _parsed = <String, _LogEntry>{};

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

  _LogEntry _entryFor(String raw) {
    if (_parsed.length > DiagnosticsService.maxLines * 2) _parsed.clear();
    return _parsed.putIfAbsent(raw, () => _LogEntry.parse(raw));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Diagnostics Log',
          style: AppTypography.sectionTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
          const SizedBox(width: AppSpacing.xs4),
        ],
      ),
      body: ValueListenableBuilder<List<String>>(
        valueListenable: DiagnosticsService.instance.logsNotifier,
        builder: (context, logs, _) {
          if (logs.isEmpty) {
            return const CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyHint(
                    icon: Icons.receipt_long_outlined,
                    title: 'No events yet',
                    message: 'No diagnostic logs recorded yet. Play something and events will show up here.',
                  ),
                ),
              ],
            );
          }

          return SelectionArea(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(child: _Summary(count: logs.length)),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg16,
                    0,
                    AppSpacing.lg16,
                    AppSpacing.xxxl32 + bottomInset,
                  ),
                  // Same look as SurfaceCard, but as a sliver so long logs stay lazily built.
                  sliver: DecoratedSliver(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                      border: Border.all(color: AppColors.divider),
                    ),
                    sliver: SliverPadding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs4),
                      sliver: SliverList.builder(
                        itemCount: logs.length,
                        itemBuilder: (context, index) {
                          return _LogLine(
                            entry: _entryFor(logs[index]),
                            showDivider: index > 0,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One log line split into timestamp, event name and payload.
///
/// Formats lines cleanly and null-safely, e.g. "[12:34:56] service_start" or
/// "[12:34:56] play {\"caller\":\"in_app\"}".
class _LogEntry {
  final String timestamp;
  final String eventName;
  final String? details;
  final bool isProblem;

  const _LogEntry({
    required this.timestamp,
    required this.eventName,
    required this.details,
    required this.isProblem,
  });

  static const _LogEntry empty = _LogEntry(timestamp: '', eventName: '', details: null, isProblem: false);

  bool get isEmpty => eventName.isEmpty && timestamp.isEmpty;

  factory _LogEntry.parse(String? rawLine) {
    if (rawLine == null || rawLine.isEmpty) return empty;

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

    String? details;
    if (dataMap != null && dataMap.isNotEmpty) {
      details = dataMap.entries.map((e) => '${e.key}: ${e.value}').join(', ');
    } else if (jsonPayload != null && jsonPayload.isNotEmpty) {
      details = jsonPayload;
    }

    final lower = eventName.toLowerCase();
    return _LogEntry(
      timestamp: timestamp,
      eventName: eventName,
      details: details,
      isProblem: lower.contains('error') || lower.contains('fail'),
    );
  }
}

class _Summary extends StatelessWidget {
  final int count;

  const _Summary({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg16,
        AppSpacing.xs4,
        AppSpacing.lg16,
        AppSpacing.lg16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent app events (playback, downloads, network), oldest first. '
            'Most links and file paths are hidden; check before sharing.',
            style: AppTypography.metadata,
          ),
          const SizedBox(height: AppSpacing.md12),
          Wrap(
            spacing: AppSpacing.sm8,
            runSpacing: AppSpacing.sm8,
            children: [
              PillTag(
                text: count == 1 ? '1 event' : '$count events',
                icon: Icons.receipt_long_outlined,
              ),
              const PillTag(
                text: 'Keeps the last ${DiagnosticsService.maxLines}',
                icon: Icons.history_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  final _LogEntry entry;
  final bool showDivider;

  const _LogLine({required this.entry, required this.showDivider});

  /// Timestamp: label scale (12/16, muted) with tabular figures so times line up.
  static final TextStyle _timeStyle = AppTypography.label.copyWith(
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Event name: metadata scale (13/18) in monospace; teal normally, red for problems.
  static final TextStyle _eventStyle = AppTypography.metadata.copyWith(
    fontFamily: 'monospace',
    fontFamilyFallback: _monoFallback,
    fontWeight: FontWeight.w600,
    color: AppColors.accent,
  );
  static final TextStyle _problemStyle = _eventStyle.copyWith(color: AppColors.error);

  /// Payload: label scale (12/16) in monospace, secondary text colour.
  static final TextStyle _detailStyle = AppTypography.label.copyWith(
    fontFamily: 'monospace',
    fontFamilyFallback: _monoFallback,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: AppColors.textSecondary,
  );

  @override
  Widget build(BuildContext context) {
    if (entry.isEmpty) return const SizedBox.shrink();

    final details = entry.details;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDivider) const Divider(height: 1, thickness: 1, indent: AppSpacing.lg16, endIndent: AppSpacing.lg16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg16, vertical: AppSpacing.md12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.timestamp.isNotEmpty) ...[
                // 1 dp centres the 16 dp timestamp line on the 18 dp event line.
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(entry.timestamp, style: _timeStyle),
                ),
                const SizedBox(width: AppSpacing.md12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.eventName, style: entry.isProblem ? _problemStyle : _eventStyle),
                    if (details != null) ...[
                      const SizedBox(height: 2),
                      Text(details, style: _detailStyle),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
