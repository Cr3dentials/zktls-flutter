import 'dart:async';

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
  String _status = 'idle';
  int _percent = 0;
  final List<String> _log = [];
  StreamSubscription<ProgressEvent>? _progressSub;

  void _append(String line) => setState(() => _log.add(line));

  Future<void> _run() async {
    ZktlsClient? client;
    try {
      client = await ZktlsClient.create(demoConfig());
      _progressSub = client.onProgress().listen((e) {
        setState(() {
          _status = e.phase.name;
          _percent = e.percent;
        });
      });
      await client.login();
      await client.capture();
      final report = await client.prove();
      if (!report.accepted) {
        _append('Not proven: ${report.verdict}');
        return;
      }
      final claim = await client.claim();
      _append('Claim: ${claim.encoded}');
    } on PlatformException catch (e) {
      _append('Error [${e.code}]: ${e.message ?? ''}');
    } finally {
      await _progressSub?.cancel();
      _progressSub = null;
      await client?.dispose();
    }
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('zkTLS example')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text('$_status $_percent%',
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _run,
                child: const Text('Run verification'),
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
