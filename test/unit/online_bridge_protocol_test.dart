import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/features/online/online_bridge_protocol.dart';

const token = '0123456789abcdef0123456789abcdef';

Map<String, Object?> media({
  String t = token,
  String u = 'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
  Object? s = 'playing',
  Object? p = 12.5,
  Object? d = 213.0,
  Object? r = 1.0,
  Object? ti = 'Never Gonna Give You Up',
  Object? ar = 'Rick Astley',
  Object? aw = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg',
  Object? n = true,
  Object? vw = 1280,
  Object? vh = 720,
  Object? e = 'play',
}) =>
    {'t': t, 'k': 'media', 'u': u, 's': s, 'p': p, 'd': d, 'r': r, 'ti': ti, 'ar': ar, 'aw': aw, 'n': n, 'vw': vw, 'vh': vh, 'e': e};

OnlineMediaState? parseMedia(Object? args) {
  final m = parseBridgeMessage(args, token: token);
  return m is BridgeMediaMessage ? m.state : null;
}

void main() {
  group('parseBridgeMessage', () {
    test('a valid media message, as the handler receives it (an argument list)', () {
      final s = parseMedia([media()])!;
      expect(s.status, OnlineMediaStatus.playing);
      expect(s.isPlaying, isTrue);
      expect(s.position, const Duration(milliseconds: 12500));
      expect(s.duration, const Duration(seconds: 213));
      expect(s.title, 'Never Gonna Give You Up');
      expect(s.artist, 'Rick Astley');
      expect(s.artworkUrl, 'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg');
      expect(s.hasNext, isTrue);
      expect(s.videoId, 'dQw4w9WgXcQ');
      expect(s.aspectRatio, closeTo(16 / 9, 0.001));
      expect(s.event, 'play');
    });

    test('also accepts a JSON string and a bare map', () {
      expect(parseMedia(jsonEncode(media())), isNotNull);
      expect(parseMedia(media()), isNotNull);
      expect(parseMedia([jsonEncode(media())]), isNotNull);
    });

    test('wrong, missing or empty token is dropped', () {
      expect(parseMedia([media(t: 'ffffffffffffffffffffffffffffffff')]), isNull);
      final noToken = media()..remove('t');
      expect(parseMedia([noToken]), isNull);
      expect(parseBridgeMessage([media()], token: ''), isNull);
    });

    test('only YouTube https pages may speak', () {
      expect(parseMedia([media(u: 'https://evil.example/watch?v=dQw4w9WgXcQ')]), isNull);
      expect(parseMedia([media(u: 'http://m.youtube.com/watch?v=dQw4w9WgXcQ')]), isNull);
      expect(parseMedia([media(u: 'https://youtube.com.evil.example/')]), isNull);
      expect(parseMedia([media(u: 'about:blank')]), isNull);
      expect(parseMedia([media(u: 'x' * 5000)]), isNull);
    });

    test('junk is dropped, never thrown', () {
      for (final junk in <Object?>[null, 42, 'not json', '[1,2]', [], [null], {'k': 'media'}, 'x' * 9000]) {
        expect(() => parseBridgeMessage(junk, token: token), returnsNormally);
        expect(parseBridgeMessage(junk, token: token), isNull, reason: '$junk'.substring(0, math.min(30, '$junk'.length)));
      }
      expect(parseBridgeMessage([{'t': token, 'k': 'nope', 'u': 'https://m.youtube.com/'}], token: token), isNull);
    });

    test('numbers are clamped; NaN-ish and wrong types fall back', () {
      final s = parseMedia([media(p: -5, d: -1, r: 99, vw: 'wide', vh: double.infinity)])!;
      expect(s.position, Duration.zero);
      expect(s.duration, isNull);
      expect(s.rate, 16.0);
      expect(s.videoWidth, 0);
      expect(s.aspectRatio, closeTo(16 / 9, 0.001), reason: 'unknown size: 16:9');
      final live = parseMedia([media(d: null)])!;
      expect(live.duration, isNull);
    });

    test('aspect ratio stays inside what Android picture-in-picture accepts', () {
      expect(parseMedia([media(vw: 4000, vh: 100)])!.aspectRatio, 2.39);
      expect(parseMedia([media(vw: 100, vh: 4000)])!.aspectRatio, closeTo(1 / 2.39, 0.0001));
      expect(parseMedia([media(vw: 1080, vh: 1920)])!.aspectRatio, closeTo(0.5625, 0.0001));
    });

    test('text is trimmed, cleaned and capped', () {
      final s = parseMedia([media(ti: '  Hello\n\tWorld\u0000  ', ar: 'A' * 500)])!;
      expect(s.title, 'Hello World');
      expect(s.artist.length, 160);
      expect(parseMedia([media(ti: 42)])!.title, '');
    });

    test('artwork only from YouTube image hosts over https; otherwise the id thumbnail', () {
      expect(parseMedia([media(aw: 'https://evil.example/x.jpg')])!.artworkUrl,
          'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
      expect(parseMedia([media(aw: 'http://i.ytimg.com/vi/x/default.jpg')])!.artworkUrl,
          'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
      expect(parseMedia([media(aw: 'https://yt3.ggpht.com/a/b=s88')])!.artworkUrl, 'https://yt3.ggpht.com/a/b=s88');
      expect(parseMedia([media(aw: '', u: 'https://m.youtube.com/')])!.artworkUrl, isNull);
    });

    test('status values', () {
      expect(parseMedia([media(s: 'paused')])!.status, OnlineMediaStatus.paused);
      expect(parseMedia([media(s: 'ended')])!.status, OnlineMediaStatus.ended);
      expect(parseMedia([media(s: 'buffering')])!.isPlaying, isTrue);
      expect(parseMedia([media(s: 'weird')])!.status, OnlineMediaStatus.none);
      expect(parseMedia([media(s: 'none')])!.isPlaying, isFalse);
    });

    test('why a pause happened: the page itself, or the phone\'s own controls', () {
      final page = parseMedia([
        {...media(s: 'paused', e: 'pause'), 'yp': true, 'na': false}
      ])!;
      expect(page.pausedByPage, isTrue);
      expect(page.pausedBySystemControls, isFalse);
      final system = parseMedia([
        {...media(s: 'paused', e: 'pause'), 'yp': false, 'na': true}
      ])!;
      expect(system.pausedBySystemControls, isTrue);
      expect(system.pausedByPage, isFalse);
      // Anything but a real true is false.
      final junk = parseMedia([
        {...media(s: 'paused', e: 'pause'), 'yp': 'true', 'na': 1}
      ])!;
      expect(junk.pausedByPage, isFalse);
      expect(junk.pausedBySystemControls, isFalse);
      expect(parseMedia([media()])!.pausedByPage, isFalse);
      expect(page == system, isFalse);
      expect(page.withStatus(OnlineMediaStatus.paused, event: 'stale').pausedByPage, isTrue);
    });

    test('pip and ready messages', () {
      final pip = parseBridgeMessage([{'t': token, 'k': 'pip', 'on': true, 'u': 'https://m.youtube.com/watch?v=dQw4w9WgXcQ'}], token: token);
      expect(pip, isA<BridgePipMessage>().having((m) => m.active, 'active', isTrue));
      final ready = parseBridgeMessage([{'t': token, 'k': 'ready', 'u': 'https://m.youtube.com/'}], token: token);
      expect(ready, isA<BridgeReadyMessage>());
    });

    test('fullscreen messages (the page saw a video enter or leave fullscreen)', () {
      const url = 'https://m.youtube.com/watch?v=dQw4w9WgXcQ';
      final on = parseBridgeMessage([{'t': token, 'k': 'fs', 'on': true, 'u': url}], token: token);
      expect(on, isA<BridgeFullscreenMessage>().having((m) => m.active, 'active', isTrue));
      final off = parseBridgeMessage([{'t': token, 'k': 'fs', 'on': 'true', 'u': url}], token: token);
      expect(off, isA<BridgeFullscreenMessage>().having((m) => m.active, 'active', isFalse), reason: 'only a real true');
      expect(parseBridgeMessage([{'t': 'ffffffffffffffffffffffffffffffff', 'k': 'fs', 'on': true, 'u': url}], token: token),
          isNull);
      expect(parseBridgeMessage([{'t': token, 'k': 'fs', 'on': true, 'u': 'https://evil.example/'}], token: token), isNull);
    });
  });

  group('BridgeCommand', () {
    test('JS calls the bridge with a fixed name and a literal argument', () {
      expect(const BridgeCommand.play().toJavaScript(), contains('b.command("play",null)'));
      expect(BridgeCommand.seekTo(const Duration(milliseconds: 61500)).toJavaScript(), contains('b.command("seekTo",61.5)'));
      expect(const BridgeCommand.setBackgroundPlay(false).toJavaScript(), contains('b.command("setBackgroundPlay",false)'));
      expect(const BridgeCommand.setPipLayout(true).toJavaScript(), contains('b.command("setPipLayout",true)'));
      expect(const BridgeCommand.next().toJavaScript(), startsWith('(function(){try{'));
    });

    test('every command maps to a handler the script knows', () {
      // assets/web/youtube_bridge.js COMMANDS keys.
      // focusSearch is gone (it looked for English labels); search,
      // exitFullscreen and exitPip are new.
      const known = {
        'play', 'pause', 'seekTo', 'next', 'previous', 'setBackgroundPlay', 'setPipLayout',
        'enterPip', 'setAutoPip', 'exitPip', 'exitFullscreen', 'search', 'requestState',
      };
      expect(BridgeCommandKind.values.map((k) => k.name).toSet(), known);
      final js = File('assets/web/youtube_bridge.js').readAsStringSync();
      final block = RegExp(r'var COMMANDS = \{([\s\S]*?)\n  \};').firstMatch(js)!.group(1)!;
      for (final name in known) {
        expect(block, contains(RegExp('\\b$name:')), reason: '$name is missing from COMMANDS');
      }
      expect(js, contains("var HANDLER = '$onlineBridgeHandlerName'"));
      expect(js, contains("var TOKEN = '$onlineBridgeTokenPlaceholder'"));
    });

    test('search text goes in as a JSON string literal that can never end early', () {
      String arg(BridgeCommand c) {
        final js = c.toJavaScript();
        final start = js.indexOf('b.command("search",') + 'b.command("search",'.length;
        final end = js.indexOf('):false;}catch');
        return js.substring(start, end);
      }

      const nasty = 'lofi"); alert(1); ("\\ \n</script> \u2028\u2029 end';
      final literal = arg(BridgeCommand.search(nasty));
      // It decodes back to the cleaned text (control characters become
      // spaces, runs of space collapse) and holds no raw quote, line break
      // or line separator that could end it.
      expect(jsonDecode(literal), 'lofi"); alert(1); ("\\ </script> end');
      expect(literal.substring(1, literal.length - 1), isNot(contains(RegExp(r'(?<!\\)"'))));
      expect(literal, isNot(contains('\n')));
      expect(literal, isNot(contains('\u2028')));
      expect(literal, isNot(contains('\u2029')));
      expect(BridgeCommand.search('a' * 500).argument, hasLength(onlineMaxSearchQuery));
      expect(BridgeCommand.search('  lofi\tbeats  ').argument, 'lofi beats');
    });

    test('exitFullscreen and exitPip take no argument', () {
      expect(const BridgeCommand.exitFullscreen().toJavaScript(), contains('b.command("exitFullscreen",null)'));
      expect(const BridgeCommand.exitPip().toJavaScript(), contains('b.command("exitPip",null)'));
    });

    test('equality', () {
      expect(const BridgeCommand.play(), const BridgeCommand.play());
      expect(BridgeCommand.seekTo(const Duration(seconds: 1)), BridgeCommand.seekTo(const Duration(seconds: 1)));
      expect(const BridgeCommand.play() == const BridgeCommand.pause(), isFalse);
    });
  });

  group('token and script', () {
    test('tokens are 32 lowercase hex characters and differ', () {
      final a = newOnlineBridgeToken();
      final b = newOnlineBridgeToken();
      expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(a == b, isFalse);
    });

    test('the placeholder is replaced; a non-hex token is refused', () {
      const src = "var TOKEN = '$onlineBridgeTokenPlaceholder';";
      expect(buildBridgeScript(src, token), "var TOKEN = '$token';");
      expect(() => buildBridgeScript(src, "x';alert(1);'"), throwsArgumentError);
    });

    test('Block ads goes in as "on" or "off", next to the token, in the real asset', () {
      final js = File('assets/web/youtube_bridge.js').readAsStringSync();
      expect(js, contains("var BLOCK_ADS = '$onlineBridgeBlockAdsPlaceholder' !== 'off';"));
      expect(onlineBridgeBlockAdsPlaceholder.allMatches(js), hasLength(1));
      final on = buildBridgeScript(js, token);
      expect(on, contains("var BLOCK_ADS = 'on' !== 'off';"), reason: 'on by default');
      final off = buildBridgeScript(js, token, blockAds: false);
      expect(off, contains("var BLOCK_ADS = 'off' !== 'off';"));
      for (final built in [on, off]) {
        expect(built, isNot(contains(onlineBridgeBlockAdsPlaceholder)));
        expect(built, isNot(contains(onlineBridgeTokenPlaceholder)));
        expect(built, contains("var TOKEN = '$token';"));
      }
    });
  });
}
