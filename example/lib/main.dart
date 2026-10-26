import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zktls_flutter/zktls_flutter.dart';

import 'settings.dart';

void main() {
  runApp(const MyApp());
}

// Placeholder configuration for "Test bridge". A real proof needs a SessionConfig
// from your backend: baseUrl, appCredential, the trust and policy bundles, and
// their pins.
SessionConfig demoConfig() => SessionConfig(
      baseUrl: 'https://example.invalid',
      appCredential: '',
      userIdHash: '',
      profileId: '',
      policyId: '',
      idempotencyKey: DateTime.now().millisecondsSinceEpoch.toString(),
      clientRegion: '',
      networkKey: 'default',
      trustBundleJson: '',
      trustOperatorKey: '',
      policyBundleJson: '',
      policyBundleDigest: '',
    );

// What the app learns from a verification: how each platform ended, never the
// data, which your server gets in signed webhooks.
List<String> describe(VerifyOutcome o) => [
      'verification ${o.verificationId}',
      ...o.platforms.map((p) => '${p.platform}: ${p.status.name}${p.reason != null ? ' (${p.reason})' : ''}'),
    ];

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final List<String> _log = [];
  bool _running = false;

  void _append(String line) => setState(() => _log.add(line));

  @override
  void initState() {
    super.initState();
    // Once, when the app starts, with the app's publishable key.
    Zktls.configure(settings.appKey).catchError(
      (Object e) => _append('configure failed - ${(e as PlatformException).code}: ${e.message ?? ''}'),
    );
  }

  // Exercises the proof-flow round-trips that do not need a live backend:
  // create() marshals a SessionConfig across and returns a sessionId; prove() on
  // a fresh session must reject (no capture yet), which runs a real verb call and
  // the error-code mapping; dispose() releases it.
  Future<void> _testBridge() async {
    setState(() => _log.clear());
    ZktlsClient? client;
    try {
      client = await ZktlsClient.create(demoConfig());
      _append('create OK - sessionId ${client.sessionId.substring(0, 8)}...');
      try {
        await client.prove();
        _append('prove: unexpectedly resolved');
      } on PlatformException catch (e) {
        _append('prove rejected as expected - code ${e.code}');
      }
      await client.dispose();
      _append('dispose OK');
      _append('Bridge round-trips OK');
    } on PlatformException catch (e) {
      _append('create failed - ${e.code}: ${e.message ?? ''}');
    }
  }

  // The partner flow: the SDK shows its own screens, runs each platform, and
  // returns once the user leaves. A reference is a value your server already
  // knows, such as a user or order id; every webhook carries it.
  Future<void> _verify() async {
    setState(() => _log.clear());
    if (settings.appKey.isEmpty) {
      _append('No app key: fill example/lib/settings.dart');
      return;
    }
    setState(() => _running = true);
    try {
      final outcome = await Zktls.verify(
        settings.platforms,
        'example-${DateTime.now().millisecondsSinceEpoch}',
      );
      describe(outcome).forEach(_append);
    } on PlatformException catch (e) {
      // A refusal: the SDK has already shown the user why.
      _append(sdkErrorCodeOf(e) == SdkErrorCode.refused
          ? 'not started: ${refusalOf(e)} - ${e.message ?? ''}'
          : '${e.code}: ${e.message ?? ''}');
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('zkTLS bridge test')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              ElevatedButton(
                onPressed: _running ? null : _testBridge,
                child: const Text('Test bridge'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _running ? null : _verify,
                child: Text('Verify ${settings.platforms.join(', ')}'),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: _log.map((l) => Text(l)).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
