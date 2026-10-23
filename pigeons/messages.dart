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

// One per tree run. Mirrors the native TreeRunConfig field for field.
class TreeRunConfig {
  TreeRunConfig({
    required this.baseUrl,
    required this.appCredential,
    required this.userIdHash,
    required this.idempotencyKey,
    required this.clientRegion,
    required this.networkKey,
    required this.platformId,
    required this.trustBundleJson,
    this.trustBundleUrl,
    required this.trustOperatorKey,
    required this.policyBundleJson,
    required this.policyBundleDigest,
    required this.relyingPartyNonceHex,
    required this.resultUrl,
    required this.resultToken,
    required this.paramsJson,
  });

  String baseUrl;
  String appCredential;
  String userIdHash;
  String idempotencyKey;
  String clientRegion;
  String networkKey;
  String platformId;
  String trustBundleJson;
  // As SessionConfig.trustBundleUrl: null or empty keeps the bundle given.
  String? trustBundleUrl;
  String trustOperatorKey;
  String policyBundleJson;
  String policyBundleDigest;
  String relyingPartyNonceHex;
  String resultUrl;
  String resultToken;
  String paramsJson;
}

// The consent screen shown before the platform's pages open. All four are
// required: a tree run has no standard text.
class TreeDisclosure {
  TreeDisclosure({
    required this.title,
    required this.message,
    required this.accept,
    required this.decline,
  });

  String title;
  String message;
  String accept;
  String decline;
}

// The native SourceEvidence enum.
enum SourceEvidence { observed, attested }

class TreeSource {
  TreeSource({
    required this.storeAs,
    required this.evidence,
    required this.rows,
    required this.pages,
    required this.bytes,
    required this.complete,
  });

  String storeAs;
  SourceEvidence evidence;
  int rows; // u64
  int pages;
  int bytes; // u64
  bool complete;
}

// What the app learns from a tree run: how it ended and each source's counts,
// never the data.
class TreeSummary {
  TreeSummary({
    required this.succeeded,
    required this.error,
    required this.sources,
    this.claim,
    required this.apiCalls,
    required this.durationMs,
    required this.delivered,
    required this.deliveryError,
    required this.resultBytes,
    required this.isolation,
    required this.handedOff,
  });

  bool succeeded;
  String error;
  List<TreeSource> sources;
  Claim? claim;
  int apiCalls;
  int durationMs; // u64
  bool delivered;
  String deliveryError;
  int resultBytes; // u64
  String isolation;
  bool handedOff;
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

// The six verbs and runTree, plus create/dispose for the session lifetime. The
// native side owns the ZktlsClient and its opaque handles, keyed by the
// returned sessionId.
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

  // A session for tree runs: a no-arg native ZktlsClient. It has no SessionConfig,
  // so the proof verbs on it fail.
  @async
  String createTree();

  @async
  TreeSummary runTree(
    String sessionId,
    TreeRunConfig config,
    TreeDisclosure disclosure,
  );

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
