import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/data/database/app_database.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/features/downloads/download_quality.dart';
import 'package:mediahub/features/library/media_context_menu.dart';
import 'package:mediahub/features/library/media_song_row.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';
import 'package:mediahub/shared/widgets/favorite_feedback_button.dart' show isFavoriteProvider;

Future<DownloadEntry> _entry(AppDatabase db, {String? audioFormat, String? qualityLabel, String? kind}) async {
  final now = DateTime(2026, 11, 23);
  final id = 'd${DateTime.now().microsecondsSinceEpoch}';
  await db.into(db.downloadsTable).insert(DownloadsTableCompanion.insert(
        id: id,
        url: 'https://example.com/a',
        host: 'example.com',
        displayName: 'a',
        fileName: 'a.mp3',
        state: 'completed',
        createdAt: now,
        updatedAt: now,
        mediaId: const Value('dl_1'),
        audioFormat: Value(audioFormat),
        qualityLabel: Value(qualityLabel),
        kind: Value(kind),
      ));
  return (db.select(db.downloadsTable)..where((t) => t.id.equals(id))).getSingle();
}

final _song = MediaItem(
  id: 'dl_1',
  uri: '/data/user/0/app/files/a.mp3',
  mediaType: MediaType.audio,
  title: 'Resham Firiri',
  artist: 'Bipana Thapa',
  durationMs: 245000,
  sizeBytes: 1,
  format: 'mp3',
  dateAdded: DateTime(2026),
  source: 'download',
);

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('the quality a download record knows', () async {
    expect(DownloadAudioQuality.of(await _entry(db, audioFormat: 'mp3-320', kind: 'audio'))?.label, 'MP3 · 320 kbps');
    expect(DownloadAudioQuality.of(await _entry(db, audioFormat: 'mp3'))?.label, 'MP3');
    expect(DownloadAudioQuality.of(await _entry(db, qualityLabel: 'MP3 192 kbps'))?.label, 'MP3 · 192 kbps');
    expect(DownloadAudioQuality.of(await _entry(db, qualityLabel: 'Audio 128 kbps'))?.label, '128 kbps');
    expect(DownloadAudioQuality.of(await _entry(db, qualityLabel: 'Opus 160 kbps'))?.short, '160 kbps');
    expect(DownloadAudioQuality.of(await _entry(db, qualityLabel: '720p', kind: 'video')), isNull);
    expect(DownloadAudioQuality.of(await _entry(db)), isNull);
  });

  test('Details shows the quality of a downloaded MP3', () async {
    await _entry(db, audioFormat: 'mp3-320', kind: 'audio');
    final quality = await downloadQualityFor(db, 'dl_1');
    final rows = MediaContextMenu.detailRows(_song, quality: quality);
    expect(rows, contains(('Quality', 'MP3 · 320 kbps', true)));
    expect(MediaContextMenu.detailRows(_song).map((r) => r.$1), isNot(contains('Quality')));
  });

  testWidgets('the song row shows the bitrate after the length', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentMediaItemProvider.overrideWith((ref) => null),
        isFavoriteProvider.overrideWith((ref, id) => Stream.value(false)),
        downloadQualityProvider.overrideWith((ref, id) async => const DownloadAudioQuality(codec: 'MP3', kbps: 320)),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(body: ListView(children: [MediaSongRow(item: _song)])),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('320 kbps', findRichText: true), findsOneWidget);
    expect(find.textContaining('4:05', findRichText: true), findsOneWidget);
  });
}
