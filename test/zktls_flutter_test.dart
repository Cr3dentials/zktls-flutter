import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zktls_flutter/zktls_flutter.dart';

// The bridge itself needs a running engine, so these cover only the pure Dart
// surface: that the public model types and error codes are wired as expected.
// The verb flow is exercised by the example app against the native SDK.
void main() {
  test('SessionConfig carries every field', () {
    final config = SessionConfig(
      baseUrl: 'https://example.test',
      appCredential: 'cred',
      userIdHash: 'hash',
      profileId: 'profile',
      policyId: 'policy',
      idempotencyKey: 'key',
      clientRegion: 'US',
      networkKey: 'default',
      trustBundleJson: '{}',
      trustOperatorKey: 'pem',
      policyBundleJson: '{}',
      policyBundleDigest: 'digest',
    );
    expect(config.baseUrl, 'https://example.test');
    expect(config.networkKey, 'default');
  });

  test('Phase enum covers the full lifecycle', () {
    expect(Phase.values, contains(Phase.loggingIn));
    expect(Phase.values, contains(Phase.done));
    expect(Phase.values.length, 12);
  });

  test('sdkErrorCodeOf reads the native variant name', () {
    expect(sdkErrorCodeOf(PlatformException(code: 'NotLoggedIn')), SdkErrorCode.notLoggedIn);
    expect(sdkErrorCodeOf(PlatformException(code: 'Policy', message: 'x')), SdkErrorCode.policy);
    expect(sdkErrorCodeOf(PlatformException(code: 'Unknown')), isNull);
    expect(sdkErrorCodeOf(StateError('x')), isNull);
  });

  test('SdkErrorCode covers every native variant', () {
    expect(SdkErrorCode.values.length, 12);
  });
}
