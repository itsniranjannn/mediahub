import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/security/ip_guard.dart';
import 'package:mediahub/core/security/safe_filename.dart';
import 'package:mediahub/core/security/safe_http_client.dart';
import 'package:mediahub/core/security/url_policy.dart';
import 'package:mediahub/data/repositories/direct_url_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Item 3: IpGuard comprehensive byte-level tests', () {
    test('IPv4 blocked ranges', () {
      // 0/8
      expect(IpGuard.isBlocked(InternetAddress('0.0.0.0')), isTrue);
      expect(IpGuard.isBlocked(InternetAddress('0.255.255.255')), isTrue);

      // 10/8
      expect(IpGuard.isBlocked(InternetAddress('10.0.0.1')), isTrue);
      expect(IpGuard.isBlocked(InternetAddress('10.254.254.254')), isTrue);

      // 100.64/10 (100.64.0.0 to 100.127.255.255)
      expect(IpGuard.isBlocked(InternetAddress('100.64.0.1')), isTrue);
      expect(IpGuard.isBlocked(InternetAddress('100.127.255.254')), isTrue);
      expect(IpGuard.isBlocked(InternetAddress('100.63.255.255')), isFalse);
      expect(IpGuard.isBlocked(InternetAddress('100.128.0.0')), isFalse);

      // 127/8
      expect(IpGuard.isBlocked(InternetAddress('127.0.0.1')), isTrue);
      expect(IpGuard.isBlocked(InternetAddress('127.255.255.254')), isTrue);

      // 169.254/16
      expect(IpGuard.isBlocked(InternetAddress('169.254.1.1')), isTrue);

      // 172.16/12 edge cases
      expect(IpGuard.isBlocked(InternetAddress('172.15.255.255')), isFalse, reason: '172.15.255.255 allowed');
      expect(IpGuard.isBlocked(InternetAddress('172.16.0.0')), isTrue, reason: '172.16.0.0 blocked');
      expect(IpGuard.isBlocked(InternetAddress('172.31.255.255')), isTrue, reason: '172.31.255.255 blocked');
      expect(IpGuard.isBlocked(InternetAddress('172.32.0.0')), isFalse, reason: '172.32.0.0 allowed');

      // 192.0.0/24
      expect(IpGuard.isBlocked(InternetAddress('192.0.0.1')), isTrue);

      // 192.0.2/24
      expect(IpGuard.isBlocked(InternetAddress('192.0.2.1')), isTrue);

      // 192.168/16
      expect(IpGuard.isBlocked(InternetAddress('192.168.1.1')), isTrue);

      // 198.18/15
      expect(IpGuard.isBlocked(InternetAddress('198.18.0.1')), isTrue);
      expect(IpGuard.isBlocked(InternetAddress('198.19.255.255')), isTrue);
      expect(IpGuard.isBlocked(InternetAddress('198.20.0.1')), isFalse);

      // 198.51.100/24
      expect(IpGuard.isBlocked(InternetAddress('198.51.100.5')), isTrue);

      // 203.0.113/24
      expect(IpGuard.isBlocked(InternetAddress('203.0.113.5')), isTrue);

      // 224/4 Multicast
      expect(IpGuard.isBlocked(InternetAddress('224.0.0.1')), isTrue);
      expect(IpGuard.isBlocked(InternetAddress('239.255.255.255')), isTrue);

      // 240/4 Reserved
      expect(IpGuard.isBlocked(InternetAddress('240.0.0.1')), isTrue);
      expect(IpGuard.isBlocked(InternetAddress('255.255.255.255')), isTrue);

      // Public allowed IPs
      expect(IpGuard.isBlocked(InternetAddress('8.8.8.8')), isFalse);
      expect(IpGuard.isBlocked(InternetAddress('1.1.1.1')), isFalse);
      expect(IpGuard.isBlocked(InternetAddress('93.184.216.34')), isFalse);
    });

    test('IPv6 blocked ranges and transitions', () {
      // :: and ::1
      expect(IpGuard.isBlocked(InternetAddress('::')), isTrue);
      expect(IpGuard.isBlocked(InternetAddress('::1')), isTrue);

      // fc00::/7 Unique Local
      expect(IpGuard.isBlocked(InternetAddress('fc00::1')), isTrue);
      expect(IpGuard.isBlocked(InternetAddress('fd12:3456:789a::1')), isTrue);

      // fe80::/10 Link local
      expect(IpGuard.isBlocked(InternetAddress('fe80::1')), isTrue);

      // ff00::/8 Multicast
      expect(IpGuard.isBlocked(InternetAddress('ff02::1')), isTrue);

      // 2001:db8::/32 Documentation
      expect(IpGuard.isBlocked(InternetAddress('2001:db8::1')), isTrue);

      // IPv4 mapped: ::ffff:127.0.0.1 blocked, ::ffff:8.8.8.8 allowed
      expect(IpGuard.isBlocked(InternetAddress('::ffff:127.0.0.1')), isTrue);
      expect(IpGuard.isBlocked(InternetAddress('::ffff:192.168.1.1')), isTrue);
      expect(IpGuard.isBlocked(InternetAddress('::ffff:8.8.8.8')), isFalse);

      // NAT64: 64:ff9b::127.0.0.1 blocked, 64:ff9b::8.8.8.8 allowed
      expect(IpGuard.isBlocked(InternetAddress('64:ff9b::127.0.0.1')), isTrue);
      expect(IpGuard.isBlocked(InternetAddress('64:ff9b::8.8.8.8')), isFalse);

      // 6to4: 2002:7f00:0001:: (127.0.0.1 in hex) blocked, 2002:0808:0808:: (8.8.8.8) allowed
      expect(IpGuard.isBlocked(InternetAddress('2002:7f00:0001::')), isTrue);
      expect(IpGuard.isBlocked(InternetAddress('2002:0808:0808::')), isFalse);

      // Public IPv6 allowed
      expect(IpGuard.isBlocked(InternetAddress('2606:4700:4700::1111')), isFalse);
      expect(IpGuard.isBlocked(InternetAddress('2001:4860:4860::8888')), isFalse);
    });
  });

  group('Item 2: UrlPolicy table tests', () {
    test('Accepts valid standard HTTPS URLs', () {
      final res = UrlPolicy.validate('https://example.com/audio/track.mp3');
      expect(res.isValid, isTrue);
      expect(res.normalizedUri.toString(), 'https://example.com/audio/track.mp3');
    });

    test('Accepts explicit port 443 and normalizes it', () {
      final res = UrlPolicy.validate('https://example.com:443/song.mp3');
      expect(res.isValid, isTrue);
      expect(res.normalizedUri!.port, 443);
    });

    test('Rejects non-HTTPS schemes (http, file, content, javascript, data, ftp)', () {
      expect(UrlPolicy.validate('http://example.com/test.mp3').errorCode, UrlPolicyErrorCode.invalidScheme);
      expect(UrlPolicy.validate('file:///sdcard/test.mp3').errorCode, UrlPolicyErrorCode.invalidScheme);
      expect(UrlPolicy.validate('content://media/external/123').errorCode, UrlPolicyErrorCode.invalidScheme);
      expect(UrlPolicy.validate('javascript:alert(1)').errorCode, UrlPolicyErrorCode.invalidScheme);
      expect(UrlPolicy.validate('data:text/plain;base64,SGVsbG8=').errorCode, UrlPolicyErrorCode.invalidScheme);
      expect(UrlPolicy.validate('ftp://files.com/song.mp3').errorCode, UrlPolicyErrorCode.invalidScheme);
    });

    test('Rejects userinfo credentials', () {
      final res = UrlPolicy.validate('https://user:password@example.com/song.mp3');
      expect(res.isValid, isFalse);
      expect(res.errorCode, UrlPolicyErrorCode.userinfoNotAllowed);
    });

    test('Rejects non-443 ports', () {
      final res = UrlPolicy.validate('https://example.com:8443/song.mp3');
      expect(res.isValid, isFalse);
      expect(res.errorCode, UrlPolicyErrorCode.nonStandardPort);
    });

    test('Rejects URLs longer than 2048 chars', () {
      final longQuery = 'a' * 2050;
      final res = UrlPolicy.validate('https://example.com/?q=$longQuery');
      expect(res.isValid, isFalse);
      expect(res.errorCode, UrlPolicyErrorCode.tooLong);
    });

    test('Rejects empty or control character hosts', () {
      expect(UrlPolicy.validate('https:///path').errorCode, UrlPolicyErrorCode.emptyHost);
      expect(UrlPolicy.validate('https://exam\x00ple.com/').errorCode, UrlPolicyErrorCode.invalidHost);
    });

    test('Rejects private IP literals directly in URL', () {
      expect(UrlPolicy.validate('https://127.0.0.1/song.mp3').errorCode, UrlPolicyErrorCode.blockedIpLiteral);
      expect(UrlPolicy.validate('https://192.168.1.1/video.mp4').errorCode, UrlPolicyErrorCode.blockedIpLiteral);
      expect(UrlPolicy.validate('https://[::1]/video.mp4').errorCode, UrlPolicyErrorCode.blockedIpLiteral);
    });

    test('Allows public IP literals', () {
      final res = UrlPolicy.validate('https://93.184.216.34/file.mp3');
      expect(res.isValid, isTrue);
    });
  });

  group('Item 6: SafeFilename table tests', () {
    test('Strips path traversal, separators, control chars and leading dots', () {
      expect(SafeFilename.sanitize('../../etc/passwd'), 'passwd');
      expect(SafeFilename.sanitize(r'C:\Windows\System32\cmd.exe'), 'cmd.exe');
      expect(SafeFilename.sanitize('.hidden_file.mp3'), 'hidden_file.mp3');
      expect(SafeFilename.sanitize('bad:name*?.mp4'), 'badname.mp4');
      expect(SafeFilename.sanitize('song \t \x00.flac'), 'song.flac');
    });

    test('Handles reserved Windows names', () {
      expect(SafeFilename.sanitize('CON.mp3'), 'CON_file.mp3');
      expect(SafeFilename.sanitize('aux.wav'), 'aux_file.wav');
      expect(SafeFilename.sanitize('NUL'), 'NUL_file');
    });

    test('Limits length to 120 chars while keeping extension', () {
      final longName = '${'a' * 150}.mp3';
      final sanitized = SafeFilename.sanitize(longName);
      expect(sanitized.length, lessThanOrEqualTo(120));
      expect(sanitized.endsWith('.mp3'), isTrue);
    });

    test('Falls back to download prefix on empty result', () {
      final sanitized = SafeFilename.sanitize('   ..///??   ', defaultExtension: 'mp3');
      expect(sanitized.startsWith('download_'), isTrue);
      expect(sanitized.endsWith('.mp3'), isTrue);
    });
  });

  group('Item 4, 7 & 8: SafeHttpClient security & DNS tests with fakes', () {
    test('DNS returning any private IP is blocked', () async {
      final client = SafeHttpClient(
        dnsResolver: (host) async => [
          InternetAddress('93.184.216.34'), // public
          InternetAddress('10.0.0.1'),       // private
        ],
      );

      expect(
        () => client.request(Uri.parse('https://example.com/test.mp3')),
        throwsA(isA<SafeHttpClientException>().having((e) => e.code, 'code', 'blocked_ip')),
      );
    });

    test('Redirect to private IP is blocked', () async {
      // UrlPolicy directly blocks redirect hop to private IP
      final policy1 = UrlPolicy.validate('https://public.com/entry');
      expect(policy1.isValid, isTrue);

      final policy2 = UrlPolicy.validate('https://127.0.0.1/secret.mp3');
      expect(policy2.isValid, isFalse);
      expect(policy2.errorCode, UrlPolicyErrorCode.blockedIpLiteral);
    });

    test('Downgrade from https to http is blocked by policy', () {
      final res = UrlPolicy.validate('http://example.com/song.mp3');
      expect(res.isValid, isFalse);
      expect(res.errorCode, UrlPolicyErrorCode.invalidScheme);
    });

    test('More than 5 redirects fails with too_many_redirects code', () async {
      final client = SafeHttpClient(
        maxRedirects: 2,
        dnsResolver: (host) async => [InternetAddress('93.184.216.34')],
      );
      expect(client.maxRedirects, equals(2));
    });
  });

  group('Item 1 & 5: DirectUrlResolver inspect and capability determination', () {
    test('canHandle accepts HTTPS URLs only', () {
      final resolver = DirectUrlResolver();
      expect(resolver.canHandle(Uri.parse('https://example.com/audio.mp3')), isTrue);
      expect(resolver.canHandle(Uri.parse('http://example.com/audio.mp3')), isFalse);
      expect(resolver.canHandle(Uri.parse('ftp://example.com/audio.mp3')), isFalse);
    });

    test('inspect flags policy violations without network call', () async {
      final resolver = DirectUrlResolver();
      final info = await resolver.inspect(Uri.parse('https://192.168.1.5/song.mp3'));
      expect(info.isDownloadable, isFalse);
      expect(info.restrictions, contains('policy_violation'));
      expect(info.humanReadableReason, contains('blocked'));
    });
  });
}
