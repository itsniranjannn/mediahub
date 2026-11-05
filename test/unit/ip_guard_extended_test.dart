import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/security/ip_guard.dart';

void main() {
  group('TASK 5.2d Item 5: Extended IpGuard IPv6 Prefixes', () {
    test('Teredo 2001::/32 is blocked', () {
      final teredo1 = InternetAddress('2001:0000:4136:e378:8000:63bf:3fff:fdd2');
      final teredo2 = InternetAddress('2001::1');
      expect(IpGuard.isBlocked(teredo1), isTrue);
      expect(IpGuard.isBlocked(teredo2), isTrue);
    });

    test('fec0::/10 Site-Local unicast is blocked', () {
      final siteLocal1 = InternetAddress('fec0::1');
      final siteLocal2 = InternetAddress('feff:ffff:ffff:ffff:ffff:ffff:ffff:ffff');
      expect(IpGuard.isBlocked(siteLocal1), isTrue);
      expect(IpGuard.isBlocked(siteLocal2), isTrue);
    });

    test('64:ff9b:1::/48 Local-Use translation prefix is blocked', () {
      final nat64Local1 = InternetAddress('64:ff9b:1::192.0.2.1');
      final nat64Local2 = InternetAddress('64:ff9b:1:ffff:ffff:ffff:ffff:ffff');
      expect(IpGuard.isBlocked(nat64Local1), isTrue);
      expect(IpGuard.isBlocked(nat64Local2), isTrue);
    });

    test('Regular global unicast IPv6 is NOT blocked', () {
      final global1 = InternetAddress('2607:f8b0:4005:805::200e'); // google.com
      final global2 = InternetAddress('2606:4700:4700::1111'); // cloudflare
      expect(IpGuard.isBlocked(global1), isFalse);
      expect(IpGuard.isBlocked(global2), isFalse);
    });
  });
}

