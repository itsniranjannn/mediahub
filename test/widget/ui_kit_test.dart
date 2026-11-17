import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/app/theme/app_colors.dart';
import 'package:mediahub/app/theme/app_spacing.dart';
import 'package:mediahub/app/theme/app_theme.dart';
import 'package:mediahub/core/services/artwork_service.dart';
import 'package:mediahub/domain/models/media_item.dart';
import 'package:mediahub/shared/widgets/media_item_tile.dart';
import 'package:mediahub/shared/widgets/ui_kit.dart';

const _channel = MethodChannel('mediahub/media_store');

/// Real Inter, so text widths match the phone.
Future<void> _loadInter() async {
  final inter = FontLoader('Inter');
  for (final weight in ['Regular', 'Medium', 'SemiBold']) {
    final bytes = File('assets/fonts/Inter-$weight.otf').readAsBytesSync();
    inter.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await inter.load();
}

Future<void> _pump(WidgetTester tester, Widget child, {double width = 360, double textScale = 1.0}) async {
  tester.view.physicalSize = Size(width * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: app!,
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}

BoxDecoration _chipDecoration(WidgetTester tester, Finder badge) {
  final container = tester.widget<Container>(find.descendant(of: badge, matching: find.byType(Container)).first);
  return container.decoration! as BoxDecoration;
}

MediaItem _video({String source = 'download'}) => MediaItem(
      id: 'video_1',
      uri: 'content://media/external/video/media/1',
      mediaType: MediaType.video,
      title: 'Trip to Pokhara',
      durationMs: 245000,
      sizeBytes: 12000000,
      dateAdded: DateTime(2026),
      source: source,
    );

void main() {
  setUpAll(_loadInter);

  group('DurationBadge', () {
    testWidgets('uses the one clock format: no leading zero, hours included', (tester) async {
      await _pump(
        tester,
        const Column(
          children: [
            DurationBadge(duration: Duration(minutes: 4, seconds: 5)),
            DurationBadge(duration: Duration(minutes: 58, seconds: 12)),
            DurationBadge(duration: Duration(hours: 1, minutes: 2, seconds: 3)),
            DurationBadge.live(),
          ],
        ),
      );
      expect(find.text('4:05'), findsOneWidget);
      expect(find.text('04:05'), findsNothing);
      expect(find.text('58:12'), findsOneWidget);
      expect(find.text('1:02:03'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
    });
  });

  group('MediaBadge', () {
    testWidgets('sits on the same dark chip as DurationBadge with a 12 dp teal glyph', (tester) async {
      await _pump(
        tester,
        const Column(
          children: [
            MediaBadge(icon: Icons.download_done_rounded, text: 'Downloaded'),
            DurationBadge(duration: Duration(minutes: 3)),
          ],
        ),
      );

      final badge = _chipDecoration(tester, find.byType(MediaBadge));
      final duration = _chipDecoration(tester, find.byType(DurationBadge));
      expect(badge.color, AppColors.overlay);
      expect(badge.color, duration.color);
      expect(badge.borderRadius, duration.borderRadius);

      final icon = tester.widget<Icon>(find.byIcon(Icons.download_done_rounded));
      expect(icon.size, 12);
      expect(icon.color, AppColors.accent);

      final text = tester.widget<Text>(find.text('Downloaded'));
      final durationText = tester.widget<Text>(find.text('3:00'));
      expect(text.style?.color, AppColors.onOverlay);
      expect(text.style?.fontSize, durationText.style?.fontSize);
      expect(text.style?.fontWeight, durationText.style?.fontWeight);
      expect(text.style?.fontFeatures, isNull, reason: 'words need no tabular figures');
      expect(durationText.style?.fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    testWidgets('a downloaded video card wears it over the cover (no filled violet pill)', (tester) async {
      await _pump(tester, ListView(children: [MediaItemTile(item: _video())]));

      expect(find.descendant(of: find.byType(MediaBadge), matching: find.text('Downloaded')), findsOneWidget);
      expect(find.byType(PillTag), findsNothing);
      expect(find.text('4:05'), findsOneWidget);
    });

    testWidgets('a device video has no badge', (tester) async {
      await _pump(tester, ListView(children: [MediaItemTile(item: _video(source: 'device'))]));
      expect(find.byType(MediaBadge), findsNothing);
      expect(find.text('Downloaded'), findsNothing);
    });
  });

  group('SectionHeader', () {
    for (final textScale in [1.0, 1.3]) {
      testWidgets('the action label ends on the 16 dp gutter at ${textScale}x text', (tester) async {
        await _pump(
          tester,
          Column(
            children: [
              SectionHeader(title: 'Recently played', actionLabel: 'See all', onAction: () {}),
              const SectionHeader(title: 'All videos'),
            ],
          ),
          textScale: textScale,
        );

        expect(tester.getRect(find.text('See all')).right, moreOrLessEquals(360 - AppSpacing.lg16, epsilon: 0.5));
        expect(tester.getRect(find.text('Recently played')).left, AppSpacing.lg16);
        expect(tester.getRect(find.text('All videos')).left, AppSpacing.lg16);

        final target = tester.getSize(find.byType(TextButton));
        expect(target.height, greaterThanOrEqualTo(AppSpacing.minTouchTarget));
        expect(target.width, greaterThanOrEqualTo(AppSpacing.minTouchTarget));
      });
    }

    testWidgets('a custom padding keeps its own gutter for the label', (tester) async {
      await _pump(
        tester,
        SectionHeader(
          title: 'Your downloads',
          actionLabel: 'Clear',
          onAction: () {},
          padding: const EdgeInsets.fromLTRB(0, AppSpacing.xxl24, 0, AppSpacing.xs4),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.text('Clear')).right, lessThanOrEqualTo(360));
    });
  });

  group('ArtworkPresenceBuilder', () {
    final item = MediaItem(
      id: 'song_1',
      uri: 'content://media/external/audio/media/77',
      mediaType: MediaType.audio,
      title: 'Song',
      durationMs: 1000,
      sizeBytes: 1,
      dateAdded: DateTime(2026),
    );

    setUp(ArtworkService.instance.clearCache);
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
      ArtworkService.instance.clearCache();
    });

    Widget probe(MediaItem? item) => ArtworkPresenceBuilder(
          item: item,
          lookupSize: 256,
          builder: (context, hasArtwork, child) => Text(hasArtwork ? 'cover' : 'no cover'),
        );

    testWidgets('turns true once the device art finishes loading', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'getArtwork') return Uint8List.fromList([1, 2, 3]).toList();
        return null;
      });

      await _pump(tester, probe(item));
      await tester.pump();
      expect(find.text('cover'), findsOneWidget);
      expect(ArtworkService.instance.hasCached(item.uri), isTrue);
    });

    testWidgets('stays false when the item has no art, and true at once for a saved thumbnail', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async => null);

      await _pump(tester, probe(item));
      await tester.pump();
      expect(find.text('no cover'), findsOneWidget);

      await _pump(tester, probe(item.copyWith(artworkPath: '/data/thumbs/77.jpg')));
      expect(find.text('cover'), findsOneWidget);

      await _pump(tester, probe(null));
      expect(find.text('no cover'), findsOneWidget);
    });

    testWidgets('starts neutral while the lookup runs, so a cold start never flashes the palette', (tester) async {
      final answer = Completer<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) => answer.future);

      await tester.pumpWidget(MaterialApp(home: probe(item)));
      expect(find.text('cover'), findsOneWidget, reason: 'the first frame assumes a cover');

      answer.complete(null);
      await tester.pump();
      await tester.pump();
      expect(find.text('no cover'), findsOneWidget, reason: 'then fades to the palette');
    });

    testWidgets('a lookup that already found nothing answers false from the first frame', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async => null);
      expect(await ArtworkService.instance.getArtwork(item.uri, size: 256), isNull);
      expect(ArtworkService.instance.isKnownMissing(item.uri, size: 256), isTrue);
      expect(ArtworkService.instance.isKnownMissing(item.uri, size: 512), isFalse, reason: 'per lookup size');

      await tester.pumpWidget(MaterialApp(home: probe(item)));
      expect(find.text('no cover'), findsOneWidget);
    });

    testWidgets('can start from "no cover" instead', (tester) async {
      final answer = Completer<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) => answer.future);

      await tester.pumpWidget(MaterialApp(
        home: ArtworkPresenceBuilder(
          item: item,
          lookupSize: 256,
          assumeArtworkWhileLoading: false,
          builder: (context, hasArtwork, child) => Text(hasArtwork ? 'cover' : 'no cover'),
        ),
      ));
      expect(find.text('no cover'), findsOneWidget);

      answer.complete(Uint8List.fromList([1, 2, 3]).toList());
      await tester.pump();
      await tester.pump();
      expect(find.text('cover'), findsOneWidget);
    });
  });

  group('SurfaceCard', () {
    LinearGradient paintedGradient(WidgetTester tester) {
      final ink = tester.widget<Ink>(find.descendant(of: find.byType(SurfaceCard), matching: find.byType(Ink)));
      return (ink.decoration! as BoxDecoration).gradient! as LinearGradient;
    }

    Widget card(Gradient gradient, {bool reduceMotion = false}) => MaterialApp(
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
            child: app!,
          ),
          home: Scaffold(body: SurfaceCard(gradient: gradient, child: const Text('card'))),
        );

    const from = LinearGradient(colors: [Color(0xFF561535), Color(0xFF0C101C)]);
    const to = LinearGradient(colors: [Color(0xFF2B2268), Color(0xFF0C101C)]);

    testWidgets('cross-fades a new gradient instead of snapping to it', (tester) async {
      await tester.pumpWidget(card(from));
      expect(paintedGradient(tester).colors.first, from.colors.first);

      await tester.pumpWidget(card(to));
      await tester.pump(const Duration(milliseconds: 100));
      final mid = paintedGradient(tester).colors.first;
      expect(mid, isNot(from.colors.first));
      expect(mid, isNot(to.colors.first));

      await tester.pumpAndSettle();
      expect(paintedGradient(tester).colors.first, to.colors.first);
    });

    testWidgets('switches at once with reduced motion', (tester) async {
      await tester.pumpWidget(card(from, reduceMotion: true));
      await tester.pumpWidget(card(to, reduceMotion: true));
      await tester.pump();
      expect(paintedGradient(tester).colors.first, to.colors.first);
    });

    testWidgets('without a gradient it is the plain surface', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SurfaceCard(child: Text('card')))));
      final material = tester.widget<Material>(
        find.descendant(of: find.byType(SurfaceCard), matching: find.byType(Material)).first,
      );
      expect(material.color, AppColors.surface);
    });
  });
}
