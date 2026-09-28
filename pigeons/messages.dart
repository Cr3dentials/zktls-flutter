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
  String trustOperatorKey;
  String policyBundleJson;
  String policyBundleDigest;
}

// The consent screen shown before the login page. Any field left null keeps the
// SDK's standard text for the profile's domains.
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

// The six verbs, plus create/dispose for the session lifetime. The native side
// owns the ZktlsClient and its opaque handles, keyed by the returned sessionId.
@HostApi()
abstract class ZktlsHostApi {
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
