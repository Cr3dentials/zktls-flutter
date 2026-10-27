import 'package:flutter/services.dart';

import 'src/messages.g.dart';

// The public types, re-exported from the generated schema so consumers import
// them from the package root. The schema's Theme is not among them: its name
// would clash with Material's Theme, so the public type is ZktlsTheme, below.
export 'src/messages.g.dart'
    show SessionConfig, Disclosure, Claim, TypedOutput, ProofReport, ProgressEvent, Phase,
        VerifyOutcome, PlatformOutcome, PlatformStatus;

// The native SdkError/SdkException variants, and two of the plugin's own. A
// failed call throws a PlatformException whose code is one of these; Transport,
// Policy and Refused also carry text in the message. InvalidArgument is
// configure given a theme color it cannot use; its message names the field.
// Internal is a fault inside the SDK that was not an SdkError.
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
  refused,
  invalidArgument,
  internal,
}

// The SdkErrorCode a call's PlatformException carries, or null for any other
// error. The exception's code is the native variant's name ("NotLoggedIn").
SdkErrorCode? sdkErrorCodeOf(Object error) {
  if (error is! PlatformException) return null;
  final code = error.code.toLowerCase();
  for (final value in SdkErrorCode.values) {
    if (value.name.toLowerCase() == code) return value;
  }
  return null;
}

// Why a verification did not start, for a Refused error ("device_not_verified",
// "app_key_invalid", ...), or null for any other error.
String? refusalOf(Object error) {
  if (sdkErrorCodeOf(error) != SdkErrorCode.refused) return null;
  final details = (error as PlatformException).details;
  return details is String ? details : null;
}

// The look of the SDK's own screens, for Zktls.configure; the native SDK's name.
// Every field optional: one left null keeps the SDK's default. Colors are
// exactly "#RRGGBB" or "#AARRGGBB" (alpha first), hex digits in either case;
// any other form makes configure throw a PlatformException with the code
// InvalidArgument. logo names an image in the app: an Android drawable or an
// iOS asset.
class ZktlsTheme {
  const ZktlsTheme({this.accent, this.background, this.text, this.logo});

  final String? accent;
  final String? background;
  final String? text;
  final String? logo;
}

// The SDK: configure once, when the app starts, then verify per user. verify
// shows the SDK's own screens, runs each platform, and returns how each platform
// ended; your server gets the data in signed webhooks.
class Zktls {
  Zktls._();

  static final ZktlsHostApi _api = ZktlsHostApi();

  // Sets the app's publishable key, zk_live_... or zk_test_..., and the look and
  // words of the SDK's screens. strings maps a screen string's key to its text.
  static Future<void> configure(
    String appKey, {
    ZktlsTheme? theme,
    Map<String, String>? strings,
  }) =>
      _api.configure(
        appKey,
        theme == null
            ? null
            : Theme(
                accent: theme.accent,
                background: theme.background,
                text: theme.text,
                logo: theme.logo,
              ),
        strings,
      );

  // Verifies the platforms (our ids, run in this order) for one user, under your
  // reference, which every webhook carries. Returns once the user leaves the flow.
  static Future<VerifyOutcome> verify(List<String> platforms, String reference) =>
      _api.verify(platforms, reference);

  // As verify, for the platforms and reference a token from your server carries.
  static Future<VerifyOutcome> verifyToken(String token) => _api.verifyToken(token);
}

// One instance per proof session, mirroring the native ZktlsClient. The native
// side owns the real client and its opaque handles, keyed by sessionId. The flow
// is login -> capture -> prove -> claim; the SDK never retries and neither should
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

  Future<void> login([Disclosure? disclosure]) =>
      _api.login(sessionId, disclosure);

  Future<void> capture() => _api.capture(sessionId);

  Future<ProofReport> prove() => _api.prove(sessionId);

  Future<Claim> claim() => _api.claim(sessionId);

  Future<void> cancel() => _api.cancel(sessionId);

  Future<void> dispose() => _api.dispose(sessionId);

  // This session's phase changes. Events for other live sessions are filtered
  // out. Backed by the generated event channel.
  Stream<ProgressEvent> onProgress() =>
      progress().where((event) => event.sessionId == sessionId);
}
