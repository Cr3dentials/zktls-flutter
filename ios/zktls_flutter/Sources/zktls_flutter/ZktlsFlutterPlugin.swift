// Pigeon 29 renamed its generated error type (what older Pigeon called FlutterError)
// to PigeonError, to stop clashing with Flutter's own FlutterError, and moved the
// registration onto <HostApi>Setup.setUp.
import Flutter
import UIKit
import ZktlsSDK

// Implements the Pigeon-generated ZktlsHostApi. One SDK ZktlsClient per session,
// keyed by a generated sessionId; Dart only ever holds the id. The host-api
// methods are async throws, matching the SDK's async actor, so they call it
// directly. Progress goes out over the Pigeon event channel.
//
// Pigeon's generated types (SessionConfig, Claim, ProofReport, TypedOutput,
// Phase) share names with the SDK's, so the SDK ones are qualified ZktlsSDK.*.
public class ZktlsFlutterPlugin: NSObject, FlutterPlugin, ZktlsHostApi {
  private var sessions: [String: ZktlsClient] = [:]
  // One lifecycle per session, on the client's own handle, as the SDK's sample
  // wires it: it holds background time and follows network changes.
  private var lifecycles: [String: ZkTlsLifecycle] = [:]
  private let lock = NSLock()
  private let progress = ProgressEmitter()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ZktlsFlutterPlugin()
    ZktlsHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    ProgressStreamHandler.register(with: registrar.messenger(), streamHandler: instance.progress)
  }

  private func client(_ sessionId: String) -> ZktlsClient? {
    lock.lock(); defer { lock.unlock() }
    return sessions[sessionId]
  }

  private func require(_ sessionId: String) throws -> ZktlsClient {
    guard let c = client(sessionId) else {
      throw PigeonError(code: "Internal", message: "unknown session", details: nil)
    }
    return c
  }

  func create(config: SessionConfig) async throws -> String {
    await register(ZktlsClient(config: toSdkConfig(config)))
  }

  func createTree() async throws -> String {
    await register(ZktlsClient())
  }

  private func register(_ client: ZktlsClient) async -> String {
    let sessionId = UUID().uuidString
    // Registered before the id is returned so no early phase is missed.
    await client.onProgress { [weak self] phase, percent in
      // A pack that attests uploads to the attester: hold background time until
      // runTree returns.
      if phase == .attesting { self?.hold(sessionId) }
      self?.progress.emit(
        ProgressEvent(sessionId: sessionId, phase: toPigeonPhase(phase), percent: Int64(percent))
      )
    }
    let lifecycle = await makeLifecycle(client)
    lock.lock()
    sessions[sessionId] = client
    lifecycles[sessionId] = lifecycle
    lock.unlock()
    return sessionId
  }

  // UIApplication is main-actor state, so the lifecycle is made there.
  @MainActor
  private func makeLifecycle(_ client: ZktlsClient) -> ZkTlsLifecycle {
    let lifecycle = ZkTlsLifecycle(host: UIApplication.shared, handle: client.lifecycleHandle)
    lifecycle.onExpiry = { client.cancel() }  // iOS ended our background time
    return lifecycle
  }

  // Idempotent, like the lifecycle's own begin and end.
  private func hold(_ sessionId: String) {
    lock.lock(); let lifecycle = lifecycles[sessionId]; lock.unlock()
    lifecycle?.begin()
  }

  private func release(_ sessionId: String) {
    lock.lock(); let lifecycle = lifecycles[sessionId]; lock.unlock()
    lifecycle?.end()
  }

  func login(sessionId: String, disclosure: Disclosure?) async throws {
    let client = try require(sessionId)
    let presenter = try await makePresenter(disclosure)
    do {
      _ = try await client.login(host: presenter)
    } catch {
      throw mapError(error)
    }
    // Only now, since the login page is the user's to take time over. Capture and
    // proof then survive the user leaving the app or changing network.
    hold(sessionId)
  }

  func capture(sessionId: String) async throws {
    let client = try require(sessionId)
    do {
      _ = try await client.capture()
    } catch {
      release(sessionId)
      throw mapError(error)
    }
  }

  func prove(sessionId: String) async throws -> ProofReport {
    let client = try require(sessionId)
    do {
      return toPigeonReport(try await client.prove())
    } catch {
      release(sessionId)
      throw mapError(error)
    }
  }

  func claim(sessionId: String) async throws -> Claim {
    let client = try require(sessionId)
    defer { release(sessionId) }
    do {
      return toPigeonClaim(try await client.claim())
    } catch {
      throw mapError(error)
    }
  }

  func runTree(sessionId: String, config: TreeRunConfig, disclosure: TreeDisclosure) async throws -> TreeSummary {
    let client = try require(sessionId)
    let host = try await makeTreeHost(disclosure)
    defer { release(sessionId) }
    do {
      return toPigeonSummary(try await client.runTree(config: toSdkTreeConfig(config), host: host))
    } catch {
      throw mapError(error)
    }
  }

  func cancel(sessionId: String) throws {
    client(sessionId)?.cancel()
  }

  func dispose(sessionId: String) async throws {
    release(sessionId)
    lock.lock()
    sessions.removeValue(forKey: sessionId)
    lifecycles.removeValue(forKey: sessionId)
    lock.unlock()
  }

  @MainActor
  private func makePresenter(_ disclosure: Disclosure?) throws -> WebViewLoginPresenter {
    guard let vc = topViewController() else {
      throw PigeonError(code: "Internal", message: "no view controller for the login WebView", details: nil)
    }
    if let disclosure = disclosure {
      return WebViewLoginPresenter(presentingFrom: vc) { _ in toSdkDisclosure(disclosure) }
    }
    return WebViewLoginPresenter(presentingFrom: vc)
  }

  @MainActor
  private func makeTreeHost(_ disclosure: TreeDisclosure) throws -> TreeWebViewHost {
    guard let vc = topViewController() else {
      throw PigeonError(code: "Internal", message: "no view controller for the tree WebView", details: nil)
    }
    return TreeWebViewHost(presentingFrom: vc, disclosure: toSdkTreeDisclosure(disclosure))
  }
}

// Pushes progress on the main thread, which the event channel requires.
private class ProgressEmitter: ProgressStreamHandler {
  private var sink: PigeonEventSink<ProgressEvent>?

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<ProgressEvent>) {
    self.sink = sink
  }

  func emit(_ event: ProgressEvent) {
    DispatchQueue.main.async { self.sink?.success(event) }
  }
}

@MainActor
private func topViewController() -> UIViewController? {
  let scene = UIApplication.shared.connectedScenes
    .compactMap { $0 as? UIWindowScene }
    .first
  let keyWindow = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
  var top = keyWindow?.rootViewController
  while let presented = top?.presentedViewController { top = presented }
  return top
}

// MARK: - Conversions

private func toSdkConfig(_ c: SessionConfig) -> ZktlsSDK.SessionConfig {
  ZktlsSDK.SessionConfig(
    baseUrl: c.baseUrl,
    appCredential: c.appCredential,
    userIdHash: c.userIdHash,
    profileId: c.profileId,
    policyId: c.policyId,
    idempotencyKey: c.idempotencyKey,
    clientRegion: c.clientRegion,
    networkKey: c.networkKey,
    trustBundleJson: c.trustBundleJson,
    trustBundleUrl: c.trustBundleUrl ?? "",
    trustOperatorKey: c.trustOperatorKey,
    policyBundleJson: c.policyBundleJson,
    policyBundleDigest: c.policyBundleDigest
  )
}

private func toSdkDisclosure(_ d: Disclosure) -> LoginDisclosure {
  LoginDisclosure(
    title: d.title ?? "",
    message: d.message ?? "",
    accept: d.accept ?? "",
    decline: d.decline ?? ""
  )
}

private func toSdkTreeConfig(_ c: TreeRunConfig) -> ZktlsSDK.TreeRunConfig {
  ZktlsSDK.TreeRunConfig(
    baseUrl: c.baseUrl,
    appCredential: c.appCredential,
    userIdHash: c.userIdHash,
    idempotencyKey: c.idempotencyKey,
    clientRegion: c.clientRegion,
    networkKey: c.networkKey,
    platformId: c.platformId,
    trustBundleJson: c.trustBundleJson,
    trustBundleUrl: c.trustBundleUrl ?? "",
    trustOperatorKey: c.trustOperatorKey,
    policyBundleJson: c.policyBundleJson,
    policyBundleDigest: c.policyBundleDigest,
    relyingPartyNonceHex: c.relyingPartyNonceHex,
    resultUrl: c.resultUrl,
    resultToken: c.resultToken,
    paramsJson: c.paramsJson
  )
}

private func toSdkTreeDisclosure(_ d: TreeDisclosure) -> ZktlsSDK.TreeDisclosure {
  ZktlsSDK.TreeDisclosure(title: d.title, message: d.message, accept: d.accept, decline: d.decline)
}

// The SDK's u64/u32 values are unsigned; Pigeon carries them as Int64. u64 is
// reinterpreted bit for bit (matching the Android Long conversion); the
// magnitudes here sit well inside Int64 anyway.
private func toPigeonReport(_ r: ZktlsSDK.ProofReport) -> ProofReport {
  ProofReport(
    accepted: r.accepted,
    verdict: r.verdict,
    nullifierHex: r.nullifierHex,
    encodedClaim: r.encodedClaim,
    proveMs: Int64(bitPattern: r.proveMs),
    sentBytes: Int64(bitPattern: r.sentBytes),
    receivedBytes: Int64(bitPattern: r.receivedBytes)
  )
}

private func toPigeonClaim(_ c: ZktlsSDK.Claim) -> Claim {
  Claim(
    outputs: c.outputs.map { TypedOutput(name: $0.name, valueJson: $0.valueJson) },
    nullifierHex: c.nullifierHex,
    profileId: c.profileId,
    policyId: c.policyId,
    verifierEpoch: Int64(c.verifierEpoch),
    issuedAt: Int64(bitPattern: c.issuedAt),
    expiresAt: Int64(bitPattern: c.expiresAt),
    signatureHex: c.signatureHex,
    encoded: c.encoded
  )
}

private func toPigeonSummary(_ s: ZktlsSDK.TreeSummary) -> TreeSummary {
  TreeSummary(
    succeeded: s.succeeded,
    error: s.error,
    sources: s.sources.map(toPigeonSource),
    claim: s.claim.map(toPigeonClaim),
    apiCalls: Int64(s.apiCalls),
    durationMs: Int64(bitPattern: s.durationMs),
    delivered: s.delivered,
    deliveryError: s.deliveryError,
    resultBytes: Int64(bitPattern: s.resultBytes),
    isolation: s.isolation,
    handedOff: s.handedOff
  )
}

private func toPigeonSource(_ s: ZktlsSDK.TreeSource) -> TreeSource {
  TreeSource(
    storeAs: s.storeAs,
    evidence: s.evidence == .attested ? .attested : .observed,
    rows: Int64(bitPattern: s.rows),
    pages: Int64(s.pages),
    bytes: Int64(bitPattern: s.bytes),
    complete: s.complete
  )
}

private func toPigeonPhase(_ p: ZktlsSDK.Phase) -> Phase {
  switch p {
  case .loggingIn: return .loggingIn
  case .collecting: return .collecting
  case .attesting: return .attesting
  case .detached: return .detached
  case .allocating: return .allocating
  case .capturing: return .capturing
  case .captured: return .captured
  case .proving: return .proving
  case .proved: return .proved
  case .claiming: return .claiming
  case .done: return .done
  case .failed: return .failed
  @unknown default: return .failed
  }
}

// Maps every SdkError to the code Dart matches on (see SdkErrorCode in
// lib/zktls_flutter.dart); anything else is Internal.
private func mapError(_ error: Error) -> PigeonError {
  guard let e = error as? SdkError else {
    return PigeonError(code: "Internal", message: (error as NSError).localizedDescription, details: nil)
  }
  switch e {
  case .NotLoggedIn: return PigeonError(code: "NotLoggedIn", message: nil, details: nil)
  case .SessionLost: return PigeonError(code: "SessionLost", message: nil, details: nil)
  case .Cancelled: return PigeonError(code: "Cancelled", message: nil, details: nil)
  case .WrongEvidence: return PigeonError(code: "WrongEvidence", message: nil, details: nil)
  case .Truncated: return PigeonError(code: "Truncated", message: nil, details: nil)
  case .ExtraResponse: return PigeonError(code: "ExtraResponse", message: nil, details: nil)
  case .Reordered: return PigeonError(code: "Reordered", message: nil, details: nil)
  case .LimitExceeded: return PigeonError(code: "LimitExceeded", message: nil, details: nil)
  case .InsufficientMemory: return PigeonError(code: "InsufficientMemory", message: nil, details: nil)
  case .Transport(let text): return PigeonError(code: "Transport", message: text, details: nil)
  case .Policy(let text): return PigeonError(code: "Policy", message: text, details: nil)
  @unknown default: return PigeonError(code: "Internal", message: nil, details: nil)
  }
}
