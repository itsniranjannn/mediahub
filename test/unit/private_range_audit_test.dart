// Copyright (c) 2026 Niranjan Katwal. All rights reserved.
// MediaHub is proprietary software. See LICENSE in the project root.
//
// The 2026-11-25 audit list: every private / reserved range is blocked both as
// an IP literal in a link (UrlPolicy) and as a resolved address (IpGuard),
// and the shorthand IPv4 spellings and localhost names never reach DNS.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediahub/core/security/ip_guard.dart';
import 'package:mediahub/core/security/url_policy.dart';

void main() {
  const blocked = [
    // 0.0.0.0/8
    '0.0.0.0', '0.1.2.3', '0.255.255.255',
    // 100.64.0.0/10 (carrier-grade NAT)
    '100.64.0.0', '100.100.1.1', '100.127.255.255',
    // link-local
    '169.254.0.1', '169.254.169.254', 'fe80::1', 'febf:ffff::1',
    // loopback
    '127.0.0.1', '127.255.255.254', '::1',
    // fc00::/7
    'fc00::1', 'fd12:3456::1', 'fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff',
    // IPv4-mapped / compatible IPv6
    '::ffff:127.0.0.1', '::ffff:10.0.0.1', '::ffff:192.168.1.1', '::ffff:169.254.169.254',
    '::ffff:100.64.0.1', '::ffff:0.0.0.1', '::ffff:7f00:1', '::127.0.0.1',
    // RFC 1918
    '10.0.0.1', '172.16.0.1', '172.31.255.255', '192.168.0.1',
    // unspecified
    '::',
  ];

  const allowed = ['8.8.8.8', '100.63.255.255', '100.128.0.0', '172.32.0.1', '2606:4700:4700::1111', '::ffff:8.8.8.8'];

  test('IpGuard blocks every listed range', () {
    for (final raw in blocked) {
      expect(IpGuard.isBlocked(InternetAddress(raw)), isTrue, reason: raw);
    }
  });

  test('IpGuard lets public addresses through', () {
    for (final raw in allowed) {
      expect(IpGuard.isBlocked(InternetAddress(raw)), isFalse, reason: raw);
    }
  });

  test('UrlPolicy refuses each blocked range as an IP literal', () {
    for (final raw in blocked) {
      final host = raw.contains(':') ? '[$raw]' : raw;
      final r = UrlPolicy.validate('https://$host/a.mp3');
      expect(r.isValid, isFalse, reason: raw);
      expect(r.errorCode, UrlPolicyErrorCode.blockedIpLiteral, reason: raw);
    }
  });

  test('shorthand IPv4 spellings and localhost names are refused before DNS', () {
    for (final host in [
      '2130706433', // 127.0.0.1 as one number
      '0x7f000001',
      '0x7f.1',
      '127.1',
      '0177.0.0.1',
      '10.1',
      'localhost',
      'LOCALHOST.',
      'media.localhost',
    ]) {
      final r = UrlPolicy.validate('https://$host/a.mp3');
      expect(r.isValid, isFalse, reason: host);
      expect(r.errorCode, UrlPolicyErrorCode.blockedIpLiteral, reason: host);
    }
  });

  test('ordinary names, numeric-looking subdomains included, still pass', () {
    for (final host in ['example.com', '123.example.com', 'cdn1.host.net', 'x.0x7f.io']) {
      expect(UrlPolicy.validate('https://$host/a.mp3').isValid, isTrue, reason: host);
    }
    expect(UrlPolicy.looksLikeNumericIpv4('1.2.3.4.5'), isFalse);
  });
}
