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
  private let lock = NSLock()
  private let progress = ProgressEmitter()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ZktlsFlutterPlugin()
    ZktlsHostApi.setUp(binaryMessenger: registrar.messenger(), api: instance)
    ProgressStreamHandler.register(with: registrar.messenger(), streamHandler: instance.progress)
  }

  private func client(_ sessionId: String) -> ZktlsClient? {
    lock.lock(); defer { lock.unlock() }
    return sessions[sessionId]
  }

  private func require(_ sessionId: String) throws -> ZktlsClient {
    guard let c = client(sessionId) else {
      throw FlutterError(code: "Internal", message: "unknown session", details: nil)
    }
    return c
  }

  func create(config: SessionConfig) async throws -> String {
    let client = ZktlsClient(config: toSdkConfig(config))
    let sessionId = UUID().uuidString
    // Registered before the id is returned so no early phase is missed.
    await client.onProgress { [weak self] phase, percent in
      self?.progress.emit(
        ProgressEvent(sessionId: sessionId, phase: toPigeonPhase(phase), percent: Int64(percent))
      )
    }
    lock.lock(); sessions[sessionId] = client; lock.unlock()
    return sessionId
  }

  func login(sessionId: String, disclosure: Disclosure?) async throws {
    let client = try require(sessionId)
    let presenter = try await makePresenter(disclosure)
    do {
      _ = try await client.login(host: presenter)
    } catch {
      throw mapError(error)
    }
  }

  func capture(sessionId: String) async throws {
    let client = try require(sessionId)
    do {
      _ = try await client.capture()
    } catch {
      throw mapError(error)
    }
  }

  func prove(sessionId: String) async throws -> ProofReport {
    let client = try require(sessionId)
    do {
      return toPigeonReport(try await client.prove())
    } catch {
      throw mapError(error)
    }
  }

  func claim(sessionId: String) async throws -> Claim {
    let client = try require(sessionId)
    do {
      return toPigeonClaim(try await client.claim())
    } catch {
      throw mapError(error)
    }
  }

  func cancel(sessionId: String) throws {
    client(sessionId)?.cancel()
  }

  func dispose(sessionId: String) async throws {
    lock.lock(); sessions.removeValue(forKey: sessionId); lock.unlock()
  }

  @MainActor
  private func makePresenter(_ disclosure: Disclosure?) throws -> WebViewLoginPresenter {
    guard let vc = topViewController() else {
      throw FlutterError(code: "Internal", message: "no view controller for the login WebView", details: nil)
    }
    if let disclosure = disclosure {
      return WebViewLoginPresenter(presentingFrom: vc) { _ in toSdkDisclosure(disclosure) }
    }
    return WebViewLoginPresenter(presentingFrom: vc)
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

private func toPigeonPhase(_ p: ZktlsSDK.Phase) -> Phase {
  switch p {
  case .loggingIn: return .loggingIn
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
private func mapError(_ error: Error) -> FlutterError {
  guard let e = error as? SdkError else {
    return FlutterError(code: "Internal", message: (error as NSError).localizedDescription, details: nil)
  }
  switch e {
  case .NotLoggedIn: return FlutterError(code: "NotLoggedIn", message: nil, details: nil)
  case .SessionLost: return FlutterError(code: "SessionLost", message: nil, details: nil)
  case .Cancelled: return FlutterError(code: "Cancelled", message: nil, details: nil)
  case .WrongEvidence: return FlutterError(code: "WrongEvidence", message: nil, details: nil)
  case .Truncated: return FlutterError(code: "Truncated", message: nil, details: nil)
  case .ExtraResponse: return FlutterError(code: "ExtraResponse", message: nil, details: nil)
  case .Reordered: return FlutterError(code: "Reordered", message: nil, details: nil)
  case .LimitExceeded: return FlutterError(code: "LimitExceeded", message: nil, details: nil)
  case .InsufficientMemory: return FlutterError(code: "InsufficientMemory", message: nil, details: nil)
  case .Transport(let text): return FlutterError(code: "Transport", message: text, details: nil)
  case .Policy(let text): return FlutterError(code: "Policy", message: text, details: nil)
  @unknown default: return FlutterError(code: "Internal", message: nil, details: nil)
  }
}
