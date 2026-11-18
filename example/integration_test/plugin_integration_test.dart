// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cr3dentials_zktls/cr3dentials_zktls.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A full verb flow needs real configuration and the native SDK binary, so the
  // end-to-end run lives in the example app. This smoke test just confirms the
  // plugin's public surface is reachable from a running app.
  testWidgets('public API is reachable', (WidgetTester tester) async {
    final config = SessionConfig(
      baseUrl: 'https://example.test',
      appCredential: '',
      userIdHash: '',
      profileId: '',
      policyId: '',
      idempotencyKey: '1',
      clientRegion: '',
      networkKey: 'default',
      trustBundleJson: '',
      trustOperatorKey: '',
      policyBundleJson: '',
      policyBundleDigest: '',
    );
    expect(config.networkKey, 'default');
  });
}
