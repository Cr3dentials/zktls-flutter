import 'package:pigeon/pigeon.dart';

// Pigeon schema: the single source of truth for the bridge. Running
//   dart run pigeon --input pigeons/messages.dart
// regenerates the typed Dart, Kotlin and Swift interfaces below. This is the
// Flutter analog of the React Native side's codegen spec.
//
// u64 native values are `int` here: Dart's int is 64-bit, so unlike JavaScript
// there is no precision loss and no need to carry them as strings.

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    kotlinOut: 'android/src/main/kotlin/ai/zktls/zktls_flutter/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'ai.zktls.zktls_flutter'),
    swiftOut: 'ios/zktls_flutter/Sources/zktls_flutter/Messages.g.swift',
    dartPackageName: 'zktls_flutter',
  ),
)

// The native Phase enum.
enum Phase {
  loggingIn,
  collecting,
  attesting,
  detached,
  allocating,
  capturing,
  captured,
  proving,
  proved,
  claiming,
  done,
  failed,
}

// One per session. Mirrors the native SessionConfig field for field.
class SessionConfig {
  SessionConfig({
    required this.baseUrl,
    required this.appCredential,
    required this.userIdHash,
    required this.profileId,
    required this.policyId,
    required this.idempotencyKey,
    required this.clientRegion,
    required this.networkKey,
    required this.trustBundleJson,
    this.trustBundleUrl,
    required this.trustOperatorKey,
    required this.policyBundleJson,
    required this.policyBundleDigest,
  });

  String baseUrl;
  String appCredential;
  String userIdHash;
  String profileId;
  String policyId;
  String idempotencyKey;
  String clientRegion;
  String networkKey;
  String trustBundleJson;
  // Where the SDK refetches the trust bundle once when an enclave's key is not
  // listed yet; null or empty keeps the bundle given.
  String? trustBundleUrl;
  String trustOperatorKey;
  String policyBundleJson;
  String policyBundleDigest;
}

// The consent screen shown before the login page. Any field left null keeps the
// SDK's standard text for the login's cookie domains.
class Disclosure {
  Disclosure({this.title, this.message, this.accept, this.decline});

  String? title;
  String? message;
  String? accept;
  String? decline;
}

class TypedOutput {
  TypedOutput({required this.name, required this.valueJson});

  String name;
  String valueJson;
}

class Claim {
  Claim({
    required this.outputs,
    required this.nullifierHex,
    required this.profileId,
    required this.policyId,
    required this.verifierEpoch,
    required this.issuedAt,
    required this.expiresAt,
    required this.signatureHex,
    required this.encoded,
  });

  List<TypedOutput> outputs;
  String nullifierHex;
  String profileId;
  String policyId;
  int verifierEpoch;
  int issuedAt; // u64 unix seconds
  int expiresAt; // u64 unix seconds
  String signatureHex;
  String encoded;
}

class ProofReport {
  ProofReport({
    required this.accepted,
    required this.verdict,
    required this.nullifierHex,
    required this.encodedClaim,
    required this.proveMs,
    required this.sentBytes,
    required this.receivedBytes,
  });

  bool accepted;
  String verdict;
  String nullifierHex;
  String encodedClaim;
  int proveMs;
  int sentBytes;
  int receivedBytes;
}

// The look of the SDK's own screens, for configure. Every field optional: one
// left null keeps the SDK's default. Colors are "#RRGGBB" or "#AARRGGBB"; logo
// names an image in the app, an Android drawable or an iOS asset.
class Theme {
  Theme({this.accent, this.background, this.text, this.logo});

  String? accent;
  String? background;
  String? text;
  String? logo;
}

// The native PlatformStatus enum.
enum PlatformStatus { done, failed, notStarted }

// How one platform ended; reason is set for a failure.
class PlatformOutcome {
  PlatformOutcome({required this.platform, required this.status, this.reason});

  String platform;
  PlatformStatus status;
  String? reason;
}

// What verify returns: never the platform's data, which goes to your server in
// a signed webhook.
class VerifyOutcome {
  VerifyOutcome({required this.verificationId, required this.platforms});

  String verificationId;
  List<PlatformOutcome> platforms;
}

class ProgressEvent {
  ProgressEvent({
    required this.sessionId,
    required this.phase,
    required this.percent,
  });

  String sessionId;
  Phase phase;
  int percent;
}

// The SDK's facade, configure and verify, and the proof flow's verbs plus
// create/dispose for the session lifetime. The native side owns each proof
// session's ZktlsClient and its opaque handles, keyed by the returned sessionId.
@HostApi()
abstract class ZktlsHostApi {
  // Sets the app's publishable key, zk_live_... or zk_test_..., and the look and
  // words of the SDK's screens. strings maps a screen string's key to its text.
  @async
  void configure(String appKey, Theme? theme, Map<String, String>? strings);

  // Verifies the platforms (our ids, run in this order) for one user, under the
  // app's reference, with the SDK's own screens. Returns once the user leaves.
  @async
  VerifyOutcome verify(List<String> platforms, String reference);

  // As verify, for the platforms and reference a token from your server carries.
  @async
  VerifyOutcome verifyToken(String token);

  @async
  String create(SessionConfig config);

  @async
  void login(String sessionId, Disclosure? disclosure);

  @async
  void capture(String sessionId);

  @async
  ProofReport prove(String sessionId);

  @async
  Claim claim(String sessionId);

  // Synchronous: must reach a verb in flight.
  void cancel(String sessionId);

  @async
  void dispose(String sessionId);
}

// Every phase change of every live session, as a typed stream. Filter by
// sessionId on the Dart side.
@EventChannelApi()
abstract class ZktlsEventApi {
  ProgressEvent progress();
}
