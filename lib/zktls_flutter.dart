import 'package:flutter/services.dart';

import 'src/messages.g.dart';

// The public types, re-exported from the generated schema so consumers import
// them from the package root.
export 'src/messages.g.dart'
    show SessionConfig, Disclosure, Claim, TypedOutput, ProofReport, ProgressEvent, Phase,
        TreeRunConfig, TreeDisclosure, TreeSummary, TreeSource, SourceEvidence;

// The native SdkError/SdkException variants. A failed verb throws a
// PlatformException whose code is one of these; Transport and Policy also carry
// text in the message. Internal is a fault inside the SDK that was not an
// SdkError.
enum SdkErrorCode {
  notLoggedIn,
  sessionLost,
  cancelled,
  wrongEvidence,
  truncated,
  extraResponse,
  reordered,
  limitExceeded,
  insufficientMemory,
  transport,
  policy,
  internal,
}

// The SdkErrorCode a verb's PlatformException carries, or null for any other
// error. The exception's code is the native variant's name ("NotLoggedIn").
SdkErrorCode? sdkErrorCodeOf(Object error) {
  if (error is! PlatformException) return null;
  final code = error.code.toLowerCase();
  for (final value in SdkErrorCode.values) {
    if (value.name.toLowerCase() == code) return value;
  }
  return null;
}

// One instance per session, mirroring the native ZktlsClient. The native side
// owns the real client and its opaque handles, keyed by sessionId. The flow is
// login -> capture -> prove -> claim; the SDK never retries and neither should
// you. Call dispose() on every terminal path.
class ZktlsClient {
  ZktlsClient._(this.sessionId, this._api);

  final String sessionId;
  final ZktlsHostApi _api;

  static Future<ZktlsClient> create(SessionConfig config) async {
    final api = ZktlsHostApi();
    final id = await api.create(config);
    return ZktlsClient._(id, api);
  }

  // A session for platform-pack runs: runTree only. It has no SessionConfig, so
  // the proof verbs on it fail.
  static Future<ZktlsClient> createTree() async {
    final api = ZktlsHostApi();
    final id = await api.createTree();
    return ZktlsClient._(id, api);
  }

  Future<void> login([Disclosure? disclosure]) =>
      _api.login(sessionId, disclosure);

  Future<void> capture() => _api.capture(sessionId);

  Future<ProofReport> prove() => _api.prove(sessionId);

  Future<Claim> claim() => _api.claim(sessionId);

  // Shows the disclosure, opens the platform's pages and runs its pack. The
  // data goes to config.resultUrl, never to the app; the summary has counts only.
  Future<TreeSummary> runTree(TreeRunConfig config, TreeDisclosure disclosure) =>
      _api.runTree(sessionId, config, disclosure);

  Future<void> cancel() => _api.cancel(sessionId);

  Future<void> dispose() => _api.dispose(sessionId);

  // This session's phase changes. Events for other live sessions are filtered
  // out. Backed by the generated event channel.
  Stream<ProgressEvent> onProgress() =>
      progress().where((event) => event.sessionId == sessionId);
}
