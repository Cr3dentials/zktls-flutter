import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zktls_flutter/zktls_flutter.dart';

void main() {
  runApp(const MyApp());
}

// Placeholder configuration. Fill these from your backend before a real run:
// baseUrl, appCredential, the trust and policy bundles, and their pins. The flow
// in _run is the real API; it completes only once these are real and the native
// SDK binary is wired in.
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

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final List<String> _log = [];

  void _append(String line) => setState(() => _log.add(line));

  // Exercises the bridge round-trips that do not need a live backend: create()
  // marshals a SessionConfig across and returns a sessionId; prove() on a fresh
  // session must reject (no capture yet), which runs a real verb call and the
  // error-code mapping; dispose() releases it. The full login->capture->prove->
  // claim flow needs real config and a live verifier.
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
                onPressed: _testBridge,
                child: const Text('Test bridge'),
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
