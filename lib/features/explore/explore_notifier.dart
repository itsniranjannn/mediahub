import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/settings_store.dart';
import 'online_models.dart';
import 'online_source.dart';

class ExploreState {
  final String query;
  final bool loading;
  final bool hasSearched;
  final List<OnlineVideo> results;
  final String? error;
  final List<String> history;

  const ExploreState({
    this.query = '',
    this.loading = false,
    this.hasSearched = false,
    this.results = const [],
    this.error,
    this.history = const [],
  });

  ExploreState copyWith({
    String? query,
    bool? loading,
    bool? hasSearched,
    List<OnlineVideo>? results,
    String? error,
    bool clearError = false,
    List<String>? history,
  }) {
    return ExploreState(
      query: query ?? this.query,
      loading: loading ?? this.loading,
      hasSearched: hasSearched ?? this.hasSearched,
      results: results ?? this.results,
      error: clearError ? null : (error ?? this.error),
      history: history ?? this.history,
    );
  }
}

class ExploreNotifier extends Notifier<ExploreState> {
  static const String _historyKey = 'explore_history';
  static const int _maxHistory = 8;
  static const int _maxQueryLength = 120;

  int _token = 0;

  @override
  ExploreState build() {
    return ExploreState(history: SettingsStore.instance.getStringList(_historyKey));
  }

  /// Runs a search. A newer search always wins over an older one that is still loading.
  Future<void> search(String raw) async {
    final q = _normalize(raw);
    if (q.isEmpty) return;

    final token = ++_token;
    state = state.copyWith(query: q, loading: true, hasSearched: true, clearError: true);

    try {
      final results = await ref.read(onlineSourceProvider).search(q);
      // The provider can be disposed while the request is in flight; touching
      // `state` then would throw an UnmountedRefException.
      if (!ref.mounted || token != _token) return;
      state = state.copyWith(results: results, loading: false);
      _remember(q);
    } on OnlineException catch (e) {
      if (!ref.mounted || token != _token) return;
      state = state.copyWith(results: const [], loading: false, error: e.message);
    } catch (_) {
      if (!ref.mounted || token != _token) return;
      state = state.copyWith(
        results: const [],
        loading: false,
        error: 'Something went wrong. Please try again.',
      );
    }
  }

  /// Trims [raw] and caps it at [_maxQueryLength] UTF-16 units without cutting
  /// an emoji (surrogate pair) in half or leaving a trailing space behind.
  static String _normalize(String raw) {
    final q = raw.trim();
    if (q.length <= _maxQueryLength) return q;
    var end = _maxQueryLength;
    final last = q.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--; // lead surrogate: drop the whole pair
    return q.substring(0, end).trimRight();
  }

  void _remember(String q) {
    final next = [q, ...state.history.where((h) => h.toLowerCase() != q.toLowerCase())]
        .take(_maxHistory)
        .toList();
    state = state.copyWith(history: next);
    SettingsStore.instance.setStringList(_historyKey, next);
  }

  void removeFromHistory(String q) {
    final next = state.history.where((h) => h != q).toList();
    state = state.copyWith(history: next);
    SettingsStore.instance.setStringList(_historyKey, next);
  }

  void clearHistory() {
    state = state.copyWith(history: const []);
    SettingsStore.instance.setStringList(_historyKey, const []);
  }
}

final exploreProvider = NotifierProvider<ExploreNotifier, ExploreState>(ExploreNotifier.new);
