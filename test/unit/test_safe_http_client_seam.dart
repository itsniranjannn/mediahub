import 'dart:io';
import 'package:mediahub/core/security/safe_http_client_seam.dart';
import 'package:mediahub/core/security/url_policy.dart';

class TestSafeHttpClientSeam implements SafeHttpClientSeam {
  const TestSafeHttpClientSeam();

  @override
  bool isIpBlocked(InternetAddress address) {
    if (address.isLoopback) return false;
    return false;
  }

  @override
  bool shouldAllowNonStandardPort(UrlPolicyErrorCode? code) => true;
}
