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

  // The SDK's facade: configure once, then verify per user. verify shows the
  // SDK's own screens over the key window's top view controller and holds its
  // own background time, so it needs none of the proof sessions' lifecycle here.
  // A theme color it cannot use throws InvalidArgument and leaves the SDK's
  // configuration as it was.
  func configure(appKey: String, theme: Theme?, strings: [String: String]?) async throws {
    let sdkTheme = try await toSdkTheme(theme)
    Zktls.configure(appKey: appKey, theme: sdkTheme, strings: strings ?? [:])
  }

  func verify(platforms: [String], reference: String) async throws -> VerifyOutcome {
    do {
      return toPigeonOutcome(try await Zktls.verify(platforms, reference: reference))
    } catch {
      throw mapError(error)
    }
  }

  func verifyToken(token: String) async throws -> VerifyOutcome {
    do {
      return toPigeonOutcome(try await Zktls.verify(token: token))
    } catch {
      throw mapError(error)
    }
  }

  private func register(_ client: ZktlsClient) async -> String {
    let sessionId = UUID().uuidString
    // Registered before the id is returned so no early phase is missed.
    await client.onProgress { [weak self] phase, percent in
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
      // SessionLost keeps the login: its recovery is another capture.
      if case .SessionLost? = error as? SdkError {} else { release(sessionId) }
      throw mapError(error)
    }
  }

  func prove(sessionId: String) async throws -> ProofReport {
    let client = try require(sessionId)
    do {
      let report = try await client.prove()
      // A rejected proof ends the session: there is no claim to fetch.
      if !report.accepted { release(sessionId) }
      return toPigeonReport(report)
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
      return WebViewLoginPresenter(presentingFrom: vc) { domains in toSdkDisclosure(disclosure, domains) }
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
    trustBundleUrl: c.trustBundleUrl ?? "",
    trustOperatorKey: c.trustOperatorKey,
    policyBundleJson: c.policyBundleJson,
    policyBundleDigest: c.policyBundleDigest
  )
}

// A field left nil keeps the SDK's standard text for the login's cookie domains.
private func toSdkDisclosure(_ d: Disclosure, _ domains: [String]) -> LoginDisclosure {
  var disclosure = LoginDisclosure.standard(domains: domains)
  if let v = d.title { disclosure.title = v }
  if let v = d.message { disclosure.message = v }
  if let v = d.accept { disclosure.accept = v }
  if let v = d.decline { disclosure.decline = v }
  return disclosure
}

// The screens' theme. A color is "#RRGGBB" or "#AARRGGBB"; the logo is an image
// asset's name in the app. A field left nil keeps the SDK's default. A color in
// any other form throws InvalidArgument.
@MainActor
private func toSdkTheme(_ t: Theme?) throws -> ZktlsTheme {
  var theme = ZktlsTheme()
  guard let t = t else { return theme }
  if let hex = t.accent { theme.accent = try themeColor("accent", hex) }
  if let hex = t.background { theme.background = try themeColor("background", hex) }
  if let hex = t.text { theme.text = try themeColor("text", hex) }
  if let name = t.logo { theme.logo = UIImage(named: name) }
  return theme
}

// The theme's color `field`. Anything but "#RRGGBB" or "#AARRGGBB", color names
// included, is an InvalidArgument error naming the field; Android refuses the
// same values with the same message.
private func themeColor(_ field: String, _ hex: String) throws -> UIColor {
  guard let c = color(hex) else {
    throw PigeonError(
      code: "InvalidArgument", message: "theme.\(field) must be #RRGGBB or #AARRGGBB", details: nil)
  }
  return c
}

// Exactly "#RRGGBB" (opaque) or "#AARRGGBB", hex digits in either case; nil for
// anything else.
private func color(_ hex: String) -> UIColor? {
  guard hex.hasPrefix("#") else { return nil }
  let digits = hex.dropFirst()
  guard digits.count == 6 || digits.count == 8,
    digits.allSatisfy({ $0.isASCII && $0.isHexDigit }),
    let v = UInt32(digits, radix: 16)
  else { return nil }
  let argb = digits.count == 6 ? (0xFF00_0000 | v) : v
  return UIColor(
    red: CGFloat((argb >> 16) & 0xFF) / 255,
    green: CGFloat((argb >> 8) & 0xFF) / 255,
    blue: CGFloat(argb & 0xFF) / 255,
    alpha: CGFloat((argb >> 24) & 0xFF) / 255
  )
}

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

private func toPigeonOutcome(_ o: ZktlsSDK.VerifyOutcome) -> VerifyOutcome {
  VerifyOutcome(
    verificationId: o.verificationId,
    platforms: o.platforms.map { p in
      let status: PlatformStatus
      switch p.status {
      case .done: status = .done
      case .failed: status = .failed
      case .notStarted: status = .notStarted
      }
      return PlatformOutcome(platform: p.platform, status: status, reason: p.reason)
    }
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
// lib/cr3dentials_zktls.dart); anything else is Internal.
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
  // The refusal code (device_not_verified, app_key_invalid, ...) is the details.
  case .Refused(let code, let message): return PigeonError(code: "Refused", message: message, details: code)
  @unknown default: return PigeonError(code: "Internal", message: nil, details: nil)
  }
}
