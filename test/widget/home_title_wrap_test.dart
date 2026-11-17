// File-style titles ("Audit_Long_Tone_5min") have no natural line-break
// opportunity, so a two-line title used to break in the middle of a word
// ("Audit_Long_Tone_5m" / "in"). The Home cards show breakableTitle(title),
// which lets the line break after an underscore, while semantics keep the
// real title.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/services/artwork_service.dart';
import 'package:mediahub/data/repositories/library_repository_impl.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/domain/repositories/library_repository.dart';
import 'package:mediahub/features/home/home_screen.dart';
import 'package:mediahub/features/music_player/playback_notifier.dart';

const _songTitle = 'Audit_Long_Tone_5min';
const _videoTitle = 'Family_Trip_Pokhara_Lakeside_2026';
const _zeroWidthSpace = '​';

const _artChannel = MethodChannel('mediahub/media_store');

MediaItem _song({String title = _songTitle}) => MediaItem(
      id: 'song_1',
      uri: 'content://media/external/audio/media/1',
      mediaType: MediaType.audio,
      title: title,
      artist: 'Test Artist',
      durationMs: 300000,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
    );

MediaItem _video() => MediaItem(
      id: 'video_1',
      uri: 'content://media/external/video/media/1',
      mediaType: MediaType.video,
      title: '$_videoTitle.mp4',
      durationMs: 120000,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
    );

/// Every Home feed answers at once: no songs, and [videos] in the rail.
class _HomeRepo implements LibraryRepository {
  final List<MediaItem> videos;
  _HomeRepo({this.videos = const []});

  @override
  Stream<List<MediaItem>> watchMediaItems({
    required MediaType mediaType,
    String? searchQuery,
    MediaSortOption sortBy = MediaSortOption.title,
    bool ascending = true,
  }) =>
      Stream.value(mediaType == MediaType.video ? videos : const []);
  @override
  Stream<List<MediaItem>> watchRecentlyPlayed({int limit = 20}) => Stream.value(const []);
  @override
  Stream<List<MediaItem>> watchMostPlayed({int limit = 20}) => Stream.value(const []);
  @override
  Stream<List<MediaItem>> watchRecentlyAdded({int limit = 20, MediaType? mediaType}) =>
      Stream.value(const []);
  @override
  Stream<List<MediaItem>> watchRecentVideos({int limit = 10}) => Stream.value(videos);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Real Inter, so widths match the phone (the test font is 1 em per glyph).
Future<void> _loadInter() async {
  final inter = FontLoader('Inter');
  for (final weight in ['Regular', 'Medium', 'SemiBold']) {
    final bytes = File('assets/fonts/Inter-$weight.otf').readAsBytesSync();
    inter.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await inter.load();
}

Future<void> _pumpHome(WidgetTester tester, {MediaItem? song, List<MediaItem> videos = const []}) async {
  tester.view.physicalSize = const Size(360 * 3, 1200 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(_HomeRepo(videos: videos)),
        currentMediaItemProvider.overrideWith((ref) => song ?? _song()),
        isPlayingProvider.overrideWith((ref) => false),
      ],
      child: MaterialApp(theme: AppTheme.darkTheme, home: const HomeScreen()),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The paragraph of the Text whose spoken label is [title].
RenderParagraph _titleParagraph(WidgetTester tester, String title) {
  final text = find.byWidgetPredicate((w) => w is Text && w.semanticsLabel == title);
  expect(text, findsOneWidget);
  return tester.renderObject<RenderParagraph>(
    find.descendant(of: text, matching: find.byType(RichText), matchRoot: true),
  );
}

/// The laid-out lines of [text], read back from the glyph boxes.
List<String> _lines(String text, List<TextBox> Function(TextSelection) boxesFor) {
  final lines = <StringBuffer>[];
  double? lineTop;
  for (var i = 0; i < text.length; i++) {
    final boxes = boxesFor(TextSelection(baseOffset: i, extentOffset: i + 1));
    // A zero-width character may have no box: it stays on the current line.
    if (lines.isEmpty || (boxes.isNotEmpty && lineTop != null && (boxes.first.top - lineTop).abs() > 1)) {
      lines.add(StringBuffer());
    }
    if (boxes.isNotEmpty) lineTop = boxes.first.top;
    lines.last.write(text[i]);
  }
  return [for (final line in lines) line.toString()];
}

List<String> _paragraphLines(RenderParagraph paragraph) =>
    _lines(paragraph.text.toPlainText(), paragraph.getBoxesForSelection);

/// How [raw] would wrap in [paragraph]'s place without wrap points.
List<String> _rawLines(RenderParagraph paragraph, String raw) {
  final painter = TextPainter(
    text: TextSpan(text: raw, style: paragraph.text.style),
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    maxLines: paragraph.maxLines,
    strutStyle: paragraph.strutStyle,
    textWidthBasis: paragraph.textWidthBasis,
  )..layout(maxWidth: paragraph.constraints.maxWidth);
  addTearDown(painter.dispose);
  return _lines(raw, painter.getBoxesForSelection);
}

String _visible(String line) => line.replaceAll(_zeroWidthSpace, '');

/// Every label, value, hint and tooltip in the semantics tree.
List<String> _spokenStrings(WidgetTester tester) {
  final root = tester.renderObject(find.byType(HomeScreen)).owner!.semanticsOwner!.rootSemanticsNode!;
  final strings = <String>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    strings.addAll([data.label, data.value, data.hint, data.tooltip].where((s) => s.isNotEmpty));
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return strings;
}

void _expectBreaksAfterUnderscores(List<String> lines, String title) {
  expect(lines, hasLength(2), reason: 'lines: $lines');
  expect(_visible(lines.first), endsWith('_'), reason: 'line 1 "${_visible(lines.first)}" ends mid-word');
  expect(lines.map(_visible).join(), title, reason: 'the whole title is shown');
}

void main() {
  setUpAll(_loadInter);

  setUp(() {
    // A device-art lookup answers (with nothing) at once, like a phone.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_artChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_artChannel, null);
    ArtworkService.instance.clearCache();
  });

  testWidgets('Continue listening wraps a file-style title after an underscore at 360 dp', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpHome(tester);

    final paragraph = _titleParagraph(tester, _songTitle);
    expect(paragraph.maxLines, 2);
    expect(paragraph.didExceedMaxLines, isFalse);

    // Without wrap points the same box breaks inside a word.
    final raw = _rawLines(paragraph, _songTitle);
    expect(raw, hasLength(2), reason: 'raw lines: $raw');
    expect(raw.first, isNot(endsWith('_')), reason: 'raw lines: $raw');

    final lines = _paragraphLines(paragraph);
    _expectBreaksAfterUnderscores(lines, _songTitle);

    // Screen readers get the real title, never the zero-width spaces.
    expect(
      find.bySemanticsLabel('Continue listening: $_songTitle by Test Artist, paused'),
      findsOneWidget,
    );
    final spoken = _spokenStrings(tester);
    expect(spoken.where((s) => s.contains(_songTitle)), isNotEmpty);
    expect(spoken.where((s) => s.contains(_zeroWidthSpace)), isEmpty);

    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('a recent video card wraps a file-style title after an underscore', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpHome(tester, videos: [_video()]);

    final paragraph = _titleParagraph(tester, _videoTitle);
    expect(paragraph.maxLines, 2);
    expect(paragraph.didExceedMaxLines, isFalse);

    final raw = _rawLines(paragraph, _videoTitle);
    expect(raw.first, isNot(endsWith('_')), reason: 'raw lines: $raw');

    _expectBreaksAfterUnderscores(_paragraphLines(paragraph), _videoTitle);

    expect(find.bySemanticsLabel('Video: $_videoTitle'), findsOneWidget);
    expect(_spokenStrings(tester).where((s) => s.contains(_zeroWidthSpace)), isEmpty);

    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('a title without underscores is shown unchanged', (tester) async {
    const plain = 'Sunrise Over Phewa Lake';
    await _pumpHome(tester, song: _song(title: plain));
    // find.text matches the displayed string, which only underscored titles change.
    expect(find.text(plain), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
