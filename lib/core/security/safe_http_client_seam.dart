import 'dart:io';
import 'package:mediahub/core/security/ip_guard.dart';
import 'package:mediahub/core/security/url_policy.dart';

/// Test seam interface that allows relaxed validation in unit test environments only.
/// In production, [StrictSafeHttpClientSeam] is used, which does not permit loopback or non-standard ports.
abstract class SafeHttpClientSeam {
  bool isIpBlocked(InternetAddress address);
  bool shouldAllowNonStandardPort(UrlPolicyErrorCode? code);
}

class StrictSafeHttpClientSeam implements SafeHttpClientSeam {
  const StrictSafeHttpClientSeam();

  @override
  bool isIpBlocked(InternetAddress address) => IpGuard.isBlocked(address);

  @override
  bool shouldAllowNonStandardPort(UrlPolicyErrorCode? code) => false;
}
