import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zktls_flutter/zktls_flutter.dart';

import 'lab_settings.dart';

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

// Your disclosure, in your words and approved for your app: the SDK shows it
// before the platform's pages open, and opens nothing if the user declines.
TreeDisclosure disclosure(String platformId) => TreeDisclosure(
      title: 'Connect your account',
      message: "The app opens $platformId's own sign-in page. You sign in there "
          'yourself; the app never sees your password. After you sign in, the app '
          'reads the data this check needs from your account on this device.',
      accept: 'Continue',
      decline: 'Not now',
    );

// What the app learns from a run: how it ended and each source's counts, never
// the data.
String describe(TreeSummary s) {
  final lines = [s.succeeded ? 'Collected' : 'Not collected: ${s.error}'];
  lines.addAll(s.sources.map((x) => '${x.storeAs}: ${x.rows} rows, ${x.pages} pages'));
  final result = s.handedOff
      ? 'handed to the attester, which posts the result'
      : s.delivered
          ? 'result delivered'
          : 'result not delivered: ${s.deliveryError}';
  lines.add('${s.durationMs ~/ 1000} s; $result');
  return lines.join('\n');
}

String _randomId() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

// One HTTP call; anything but a 200 throws.
Future<String> _send(String method, String url,
    {Map<String, String> headers = const {}, String? body}) async {
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await http.openUrl(method, Uri.parse(url));
    headers.forEach(req.headers.set);
    if (body != null) {
      final bytes = utf8.encode(body);
      req.contentLength = bytes.length;
      req.add(bytes);
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw HttpException('$url answered ${res.statusCode}');
    }
    return text;
  } finally {
    http.close();
  }
}

// Your backend's call for a run: it issues the run's result URL and token. A
// test server (pack-lab) stands in for it and takes the app credential.
Future<({String url, String token, String params})> issueRun(String platformId) async {
  final reply = jsonDecode(await _send(
    'POST',
    labSettings.runsUrl,
    headers: {
      'Authorization': 'Bearer ${labSettings.appCredential}',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'platform_id': platformId}),
  )) as Map<String, dynamic>;
  final params = reply['params'];
  return (
    url: reply['result_url'] as String,
    token: reply['result_token'] as String,
    params: params == null ? '' : jsonEncode(params),
  );
}

// The trust bundle and the pinned policy bundle, which a pack that attests
// needs; '' when unset.
Future<({String trust, String policy})> bundles() async => (
      trust: labSettings.trustBundleUrl.isEmpty ? '' : await _send('GET', labSettings.trustBundleUrl),
      policy: labSettings.policyBundleUrl.isEmpty ? '' : await _send('GET', labSettings.policyBundleUrl),
    );

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final List<String> _log = [];
  String? _platform = labSettings.platforms.firstOrNull;
  String _status = '';
  bool _running = false;

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

  // A platform's pack, the user present: the SDK shows the disclosure, opens the
  // platform's sign-in page and collects in the page. The data reaches the
  // backend at the result URL; the app gets a summary only.
  Future<void> _runPack() async {
    final platformId = _platform;
    if (labSettings.runsUrl.isEmpty || platformId == null) {
      setState(() => _log
        ..clear()
        ..add('No lab settings: fill example/lib/lab_settings.dart from tree.json'));
      return;
    }
    setState(() {
      _log.clear();
      _status = '';
      _running = true;
    });
    ZktlsClient? client;
    StreamSubscription<ProgressEvent>? progress;
    try {
      final run = await issueRun(platformId);
      final b = await bundles();
      client = await ZktlsClient.createTree();
      progress = client.onProgress().listen(
          (e) => setState(() => _status = '${e.phase.name} ${e.percent}%'));
      final summary = await client.runTree(
        TreeRunConfig(
          baseUrl: labSettings.baseUrl,
          appCredential: labSettings.appCredential,
          userIdHash: labSettings.userIdHash,
          idempotencyKey: _randomId(),
          clientRegion: labSettings.clientRegion,
          networkKey: 'sample',
          platformId: platformId,
          trustBundleJson: b.trust,
          trustBundleUrl: labSettings.trustBundleUrl,
          trustOperatorKey: labSettings.trustOperatorKey,
          policyBundleJson: b.policy,
          policyBundleDigest: labSettings.policyBundleDigest,
          relyingPartyNonceHex: '',
          resultUrl: run.url,
          resultToken: run.token,
          paramsJson: run.params,
        ),
        disclosure(platformId),
      );
      _append(describe(summary));
      _append('isolation: ${summary.isolation}');
    } on PlatformException catch (e) {
      _append('runTree failed - ${e.code}: ${e.message ?? ''}');
    } catch (e) {
      _append('No run: $e');
    } finally {
      await progress?.cancel();
      await client?.dispose();
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
                onPressed: _testBridge,
                child: const Text('Test bridge'),
              ),
              const SizedBox(height: 16),
              DropdownButton<String>(
                value: _platform,
                hint: const Text('Platform'),
                items: labSettings.platforms
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: _running ? null : (p) => setState(() => _platform = p),
              ),
              ElevatedButton(
                onPressed: _running ? null : _runPack,
                child: const Text('Run a platform pack'),
              ),
              Text(_status),
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
