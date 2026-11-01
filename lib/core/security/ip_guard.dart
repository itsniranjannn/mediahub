import 'dart:io';

class IpGuard {
  IpGuard._();

  /// Returns true if [address] is a private, reserved, loopback, or otherwise blocked IP.
  static bool isBlocked(InternetAddress address) {
    if (address.type == InternetAddressType.IPv4) {
      return isBlockedIpv4Bytes(address.rawAddress);
    } else if (address.type == InternetAddressType.IPv6) {
      return isBlockedIpv6(address);
    }
    return true; // Block unknown address types
  }

  /// Classifies IPv4 bytes:
  /// - 0.0.0.0/8 (0.0.0.0 - 0.255.255.255)
  /// - 10.0.0.0/8 (10.0.0.0 - 10.255.255.255)
  /// - 100.64.0.0/10 (100.64.0.0 - 100.127.255.255)
  /// - 127.0.0.0/8 (127.0.0.0 - 127.255.255.255)
  /// - 169.254.0.0/16 (169.254.0.0 - 169.254.255.255)
  /// - 172.16.0.0/12 (172.16.0.0 - 172.31.255.255)
  /// - 192.0.0.0/24 (192.0.0.0 - 192.0.0.255)
  /// - 192.0.2.0/24 (192.0.2.0 - 192.0.2.255)
  /// - 192.168.0.0/16 (192.168.0.0 - 192.168.255.255)
  /// - 198.18.0.0/15 (198.18.0.0 - 198.19.255.255)
  /// - 198.51.100.0/24 (198.51.100.0 - 198.51.100.255)
  /// - 203.0.113.0/24 (203.0.113.0 - 203.0.113.255)
  /// - 224.0.0.0/4 (224.0.0.0 - 239.255.255.255) Multicast
  /// - 240.0.0.0/4 (240.0.0.0 - 255.255.255.254) Reserved
  /// - 255.255.255.255 Broadcast
  static bool isBlockedIpv4Bytes(List<int> bytes) {
    if (bytes.length != 4) return true;
    final b0 = bytes[0];
    final b1 = bytes[1];
    final b2 = bytes[2];
    final b3 = bytes[3];

    // 0.0.0.0/8
    if (b0 == 0) return true;

    // 10.0.0.0/8
    if (b0 == 10) return true;

    // 100.64.0.0/10 (100.01000000.0.0 to 100.01111111.255.255 -> b1 & 0xC0 == 64)
    if (b0 == 100 && (b1 & 0xC0) == 64) return true;

    // 127.0.0.0/8
    if (b0 == 127) return true;

    // 169.254.0.0/16
    if (b0 == 169 && b1 == 254) return true;

    // 172.16.0.0/12 (172.00010000.0.0 to 172.00011111.255.255 -> b1 & 0xF0 == 16)
    if (b0 == 172 && (b1 & 0xF0) == 16) return true;

    // 192.0.0.0/24
    if (b0 == 192 && b1 == 0 && b2 == 0) return true;

    // 192.0.2.0/24 (TEST-NET-1)
    if (b0 == 192 && b1 == 0 && b2 == 2) return true;

    // 192.168.0.0/16
    if (b0 == 192 && b1 == 168) return true;

    // 198.18.0.0/15 (198.00010010.0.0 to 198.00010011.255.255 -> b1 & 0xFE == 18)
    if (b0 == 198 && (b1 & 0xFE) == 18) return true;

    // 198.51.100.0/24 (TEST-NET-2)
    if (b0 == 198 && b1 == 51 && b2 == 100) return true;

    // 203.0.113.0/24 (TEST-NET-3)
    if (b0 == 203 && b1 == 0 && b2 == 113) return true;

    // 224.0.0.0/4 Multicast (b0 & 0xF0 == 224)
    if ((b0 & 0xF0) == 224) return true;

    // 240.0.0.0/4 Reserved (b0 & 0xF0 == 240) which also covers 255.255.255.255
    if ((b0 & 0xF0) == 240) return true;

    // 255.255.255.255
    if (b0 == 255 && b1 == 255 && b2 == 255 && b3 == 255) return true;

    return false;
  }

  /// Classifies IPv6 bytes:
  /// - :: (unspecified, 16 zero bytes)
  /// - ::1 (loopback)
  /// - fc00::/7 Unique Local Address (first byte & 0xFE == 0xFC)
  /// - fe80::/10 Link Local (first byte == 0xFE and (second byte & 0xC0 == 0x80))
  /// - ff00::/8 Multicast (first byte == 0xFF)
  /// - 2001:db8::/32 Documentation (first 4 bytes: 0x20, 0x01, 0x0D, 0xB8)
  /// - IPv4-mapped (::ffff:0:0/96 or ::ffff:a.b.c.d) -> check embedded IPv4
  /// - NAT64 (64:ff9b::/96) -> check embedded IPv4 (last 4 bytes)
  /// - 6to4 (2002::/16) -> bytes 2..5 are IPv4, re-check embedded IPv4
  static bool isBlockedIpv6(InternetAddress address) {
    final bytes = address.rawAddress;
    if (bytes.length != 16) return true;

    // :: (unspecified)
    bool allZero = true;
    for (int i = 0; i < 16; i++) {
      if (bytes[i] != 0) {
        allZero = false;
        break;
      }
    }
    if (allZero) return true;

    // ::1 (loopback)
    bool isLoopback = true;
    for (int i = 0; i < 15; i++) {
      if (bytes[i] != 0) {
        isLoopback = false;
        break;
      }
    }
    if (isLoopback && bytes[15] == 1) return true;

    // fc00::/7 (bytes[0] & 0xFE == 0xFC) -> covers fc00::/8 and fd00::/8
    if ((bytes[0] & 0xFE) == 0xFC) return true;

    // fe80::/10 (bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80)
    if (bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80) return true;

    // ff00::/8 (bytes[0] == 0xFF)
    if (bytes[0] == 0xFF) return true;

    // 2001:db8::/32 (0x20, 0x01, 0x0D, 0xB8)
    if (bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0D && bytes[3] == 0xB8) return true;

    // Teredo: 2001::/32 (0x20, 0x01, 0x00, 0x00)
    if (bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x00 && bytes[3] == 0x00) return true;

    // fec0::/10 Site-Local unicast (RFC 3879 deprecated): bytes[0] == 0xFE && (bytes[1] & 0xC0 == 0xC0)
    if (bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0xC0) return true;

    // Local-Use IPv4/IPv6 Translation Prefix: 64:ff9b:1::/48
    // bytes 0..5: 0x00, 0x64, 0xFF, 0x9B, 0x00, 0x01
    if (bytes[0] == 0x00 &&
        bytes[1] == 0x64 &&
        bytes[2] == 0xFF &&
        bytes[3] == 0x9B &&
        bytes[4] == 0x00 &&
        bytes[5] == 0x01) {
      return true;
    }

    // IPv4-mapped (::ffff:a.b.c.d) or IPv4-compatible (::a.b.c.d)
    // First 10 bytes must be 0x00
    bool first10Zero = true;
    for (int i = 0; i < 10; i++) {
      if (bytes[i] != 0) {
        first10Zero = false;
        break;
      }
    }
    if (first10Zero) {
      if ((bytes[10] == 0xFF && bytes[11] == 0xFF) || (bytes[10] == 0x00 && bytes[11] == 0x00)) {
        final ipv4Bytes = [bytes[12], bytes[13], bytes[14], bytes[15]];
        return isBlockedIpv4Bytes(ipv4Bytes);
      }
    }

    // NAT64 well-known prefix: 64:ff9b::/96
    // bytes 0..3: 0x00, 0x64, 0xFF, 0x9B; bytes 4..11: 0x00
    if (bytes[0] == 0x00 && bytes[1] == 0x64 && bytes[2] == 0xFF && bytes[3] == 0x9B) {
      bool middleZero = true;
      for (int i = 4; i < 12; i++) {
        if (bytes[i] != 0) {
          middleZero = false;
          break;
        }
      }
      if (middleZero) {
        final ipv4Bytes = [bytes[12], bytes[13], bytes[14], bytes[15]];
        return isBlockedIpv4Bytes(ipv4Bytes);
      }
    }

    // 6to4: 2002::/16
    // bytes 0..1: 0x20, 0x02. Embedded IPv4 in bytes 2..5
    if (bytes[0] == 0x20 && bytes[1] == 0x02) {
      final ipv4Bytes = [bytes[2], bytes[3], bytes[4], bytes[5]];
      return isBlockedIpv4Bytes(ipv4Bytes);
    }

    return false;
  }
}

