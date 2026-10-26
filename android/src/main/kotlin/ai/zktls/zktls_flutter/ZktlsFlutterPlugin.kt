package ai.zktls.zktls_flutter

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicReference
import ai.zktls.sdk.SdkException
import ai.zktls.sdk.WebViewLoginPresenter
import ai.zktls.sdk.Zktls
import ai.zktls.sdk.ZkTlsLifecycle
import ai.zktls.sdk.ZkTlsSessionService
import ai.zktls.sdk.ZktlsClient
import ai.zktls.sdk.Claim as SdkClaim
import ai.zktls.sdk.LoginDisclosure as SdkLoginDisclosure
import ai.zktls.sdk.Phase as SdkPhase
import ai.zktls.sdk.ProofReport as SdkProofReport
import ai.zktls.sdk.PlatformStatus as SdkPlatformStatus
import ai.zktls.sdk.SessionConfig as SdkSessionConfig
import ai.zktls.sdk.TypedOutput as SdkTypedOutput
import ai.zktls.sdk.VerifyOutcome as SdkVerifyOutcome
import ai.zktls.sdk.ZktlsTheme as SdkZktlsTheme

// Implements the Pigeon-generated ZktlsHostApi. One native ZktlsClient per
// session, keyed by a generated sessionId; Dart only ever holds the id. The
// host-api methods are suspend, matching the SDK's own suspend verbs, so Pigeon
// runs them and marshals the result. Progress goes out over the Pigeon event
// channel.
class ZktlsFlutterPlugin : FlutterPlugin, ActivityAware, ZktlsHostApi {
  private val sessions = ConcurrentHashMap<String, ZktlsClient>()
  // One lifecycle per session, on the client's own handle, as the SDK's sample
  // wires it: it follows network changes and, with the foreground service, keeps
  // a session alive when the user leaves the app.
  private val lifecycles = ConcurrentHashMap<String, ZkTlsLifecycle>()
  // ZkTlsSessionService has a single slot: the session that started it owns it,
  // and a later session goes on without the service rather than take it over.
  private val serviceOwner = AtomicReference<String?>(null)
  private val main = Handler(Looper.getMainLooper())
  private val progress = ProgressEmitter()
  private var activity: Activity? = null
  private lateinit var context: Context

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    ZktlsHostApi.setUp(binding.binaryMessenger, this)
    ProgressStreamHandler.register(binding.binaryMessenger, progress)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    ZktlsHostApi.setUp(binding.binaryMessenger, null)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    activity = null
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override suspend fun create(config: SessionConfig): String =
    register(ZktlsClient(toSdkConfig(config)))

  // The SDK's facade: configure once, then verify per user. verify shows the
  // SDK's own screens over the current activity and keeps its session alive
  // itself, so it needs none of the proof sessions' lifecycle here.
  override suspend fun configure(appKey: String, theme: Theme?, strings: Map<String, String>?) = guarded {
    Zktls.configure(appKey, toSdkTheme(theme), strings ?: emptyMap())
  }

  override suspend fun verify(platforms: List<String>, reference: String): VerifyOutcome = guarded {
    val act = activity ?: throw FlutterError("Internal", "no current activity for the SDK's screens")
    toPigeonOutcome(Zktls.verify(act, platforms, reference))
  }

  override suspend fun verifyToken(token: String): VerifyOutcome = guarded {
    val act = activity ?: throw FlutterError("Internal", "no current activity for the SDK's screens")
    toPigeonOutcome(Zktls.verify(act, token))
  }

  private fun register(client: ZktlsClient): String {
    val sessionId = UUID.randomUUID().toString()
    // Registered before the id is returned so no early phase is missed.
    client.onProgress { phase, percent ->
      progress.emit(ProgressEvent(sessionId, toPigeonPhase(phase), percent.toLong()))
    }
    lifecycles[sessionId] = ZkTlsLifecycle(context, client.lifecycleHandle)
    sessions[sessionId] = client
    return sessionId
  }

  override suspend fun login(sessionId: String, disclosure: Disclosure?) = guarded {
    val client = requireSession(sessionId)
    val act = activity ?: throw FlutterError("Internal", "no current activity for the login WebView")
    val presenter = if (disclosure != null) {
      WebViewLoginPresenter(act) { domains -> toSdkDisclosure(disclosure, domains) }
    } else {
      WebViewLoginPresenter(act)
    }
    client.login(presenter)
    // Only now, since the login page is the user's to take time over. Capture
    // and proof then survive the user leaving the app or changing network.
    main.post { hold(sessionId) }
    Unit
  }

  override suspend fun capture(sessionId: String) = guarded {
    releasingOnFailure(sessionId) { requireSession(sessionId).capture() }
    Unit
  }

  override suspend fun prove(sessionId: String): ProofReport = guarded {
    val report = releasingOnFailure(sessionId) { requireSession(sessionId).prove() }
    // A rejected proof ends the session: there is no claim to fetch.
    if (!report.accepted) release(sessionId)
    toPigeonReport(report)
  }

  override suspend fun claim(sessionId: String): Claim = guarded {
    try {
      toPigeonClaim(requireSession(sessionId).claim())
    } finally {
      release(sessionId)
    }
  }

  override fun cancel(sessionId: String) {
    sessions[sessionId]?.cancel()
  }

  override suspend fun dispose(sessionId: String) {
    release(sessionId)
    lifecycles.remove(sessionId)
    sessions.remove(sessionId)
  }

  // Starts following the network and the foreground service for a session. On the
  // main thread. From API 31 a background start throws: the session then goes on
  // without the service.
  private fun hold(sessionId: String) {
    val client = sessions[sessionId] ?: return
    val lifecycle = lifecycles[sessionId] ?: return
    lifecycle.begin()
    if (!serviceOwner.compareAndSet(null, sessionId)) return
    try {
      ZkTlsSessionService.start(context, lifecycle) { client.cancel() }
    } catch (e: IllegalStateException) {
      // ForegroundServiceStartNotAllowedException: the app is in the background.
      // start set the slot before it threw, so clear it.
      serviceOwner.set(null)
      ZkTlsSessionService.stop(context)
    }
  }

  // Ends what hold started. Idempotent, so every exit may call it.
  private fun release(sessionId: String) {
    lifecycles[sessionId]?.end()
    if (serviceOwner.compareAndSet(sessionId, null)) ZkTlsSessionService.stop(context)
  }

  // A failed step after login ends the session: neither the SDK nor the bridge
  // retries. SessionLost keeps the login: its recovery is another capture.
  private suspend fun <T> releasingOnFailure(sessionId: String, block: suspend () -> T): T = try {
    block()
  } catch (e: Throwable) {
    if (e !is SdkException.SessionLost) release(sessionId)
    throw e
  }

  private fun requireSession(sessionId: String): ZktlsClient =
    sessions[sessionId] ?: throw FlutterError("Internal", "unknown session")

  // Maps SdkException to a coded FlutterError so Dart sees the right error code
  // (see SdkErrorCode in lib/zktls_flutter.dart); anything else is Internal.
  private suspend fun <T> guarded(block: suspend () -> T): T = try {
    block()
  } catch (e: FlutterError) {
    throw e
  } catch (e: SdkException) {
    throw when (e) {
      is SdkException.NotLoggedIn -> FlutterError("NotLoggedIn")
      is SdkException.SessionLost -> FlutterError("SessionLost")
      is SdkException.Cancelled -> FlutterError("Cancelled")
      is SdkException.WrongEvidence -> FlutterError("WrongEvidence")
      is SdkException.Truncated -> FlutterError("Truncated")
      is SdkException.ExtraResponse -> FlutterError("ExtraResponse")
      is SdkException.Reordered -> FlutterError("Reordered")
      is SdkException.LimitExceeded -> FlutterError("LimitExceeded")
      is SdkException.InsufficientMemory -> FlutterError("InsufficientMemory")
      is SdkException.Transport -> FlutterError("Transport", e.v1)
      is SdkException.Policy -> FlutterError("Policy", e.v1)
      // The refusal code (device_not_verified, app_key_invalid, ...) is the details.
      is SdkException.Refused -> FlutterError("Refused", e.message, e.code)
    }
  } catch (e: Throwable) {
    throw FlutterError("Internal", e.message)
  }

  private fun toSdkConfig(c: SessionConfig) = SdkSessionConfig(
    baseUrl = c.baseUrl,
    appCredential = c.appCredential,
    userIdHash = c.userIdHash,
    profileId = c.profileId,
    policyId = c.policyId,
    idempotencyKey = c.idempotencyKey,
    clientRegion = c.clientRegion,
    networkKey = c.networkKey,
    trustBundleJson = c.trustBundleJson,
    trustBundleUrl = c.trustBundleUrl ?: "",
    trustOperatorKey = c.trustOperatorKey,
    policyBundleJson = c.policyBundleJson,
    policyBundleDigest = c.policyBundleDigest,
  )

  // A field left null keeps the SDK's standard text for the login's cookie domains.
  private fun toSdkDisclosure(d: Disclosure, domains: List<String>): SdkLoginDisclosure {
    val standard = SdkLoginDisclosure.standard(domains)
    return SdkLoginDisclosure(
      title = d.title ?: standard.title,
      message = d.message ?: standard.message,
      accept = d.accept ?: standard.accept,
      decline = d.decline ?: standard.decline,
    )
  }

  // The screens' theme. A color is "#RRGGBB" or "#AARRGGBB"; the logo is a
  // drawable's name in the app. A field left null keeps the SDK's default.
  private fun toSdkTheme(t: Theme?): SdkZktlsTheme {
    if (t == null) return SdkZktlsTheme()
    val logo = t.logo?.let {
      context.resources.getIdentifier(it, "drawable", context.packageName).takeIf { id -> id != 0 }
    }
    return SdkZktlsTheme(
      accent = t.accent?.let { Color.parseColor(it) },
      background = t.background?.let { Color.parseColor(it) },
      text = t.text?.let { Color.parseColor(it) },
      logo = logo,
    )
  }

  private fun toPigeonReport(r: SdkProofReport) = ProofReport(
    accepted = r.accepted,
    verdict = r.verdict,
    nullifierHex = r.nullifierHex,
    encodedClaim = r.encodedClaim,
    proveMs = r.proveMs.toLong(),
    sentBytes = r.sentBytes.toLong(),
    receivedBytes = r.receivedBytes.toLong(),
  )

  private fun toPigeonClaim(c: SdkClaim) = Claim(
    outputs = c.outputs.map { TypedOutput(it.name, it.valueJson) },
    nullifierHex = c.nullifierHex,
    profileId = c.profileId,
    policyId = c.policyId,
    verifierEpoch = c.verifierEpoch.toLong(),
    issuedAt = c.issuedAt.toLong(),
    expiresAt = c.expiresAt.toLong(),
    signatureHex = c.signatureHex,
    encoded = c.encoded,
  )

  private fun toPigeonOutcome(o: SdkVerifyOutcome) = VerifyOutcome(
    verificationId = o.verificationId,
    platforms = o.platforms.map {
      PlatformOutcome(
        platform = it.platform,
        status = when (it.status) {
          SdkPlatformStatus.DONE -> PlatformStatus.DONE
          SdkPlatformStatus.FAILED -> PlatformStatus.FAILED
          SdkPlatformStatus.NOT_STARTED -> PlatformStatus.NOT_STARTED
        },
        reason = it.reason,
      )
    },
  )

  private fun toPigeonPhase(p: SdkPhase): Phase = when (p) {
    SdkPhase.LOGGING_IN -> Phase.LOGGING_IN
    SdkPhase.COLLECTING -> Phase.COLLECTING
    SdkPhase.ATTESTING -> Phase.ATTESTING
    SdkPhase.DETACHED -> Phase.DETACHED
    SdkPhase.ALLOCATING -> Phase.ALLOCATING
    SdkPhase.CAPTURING -> Phase.CAPTURING
    SdkPhase.CAPTURED -> Phase.CAPTURED
    SdkPhase.PROVING -> Phase.PROVING
    SdkPhase.PROVED -> Phase.PROVED
    SdkPhase.CLAIMING -> Phase.CLAIMING
    SdkPhase.DONE -> Phase.DONE
    SdkPhase.FAILED -> Phase.FAILED
  }
}

// Holds the Dart listener's sink and pushes progress events on the main thread,
// which the event channel requires.
private class ProgressEmitter : ProgressStreamHandler() {
  @Volatile private var sink: PigeonEventSink<ProgressEvent>? = null
  private val main = Handler(Looper.getMainLooper())

  override fun onListen(p0: Any?, sink: PigeonEventSink<ProgressEvent>) {
    this.sink = sink
  }

  override fun onCancel(p0: Any?) {
    sink = null
  }

  fun emit(event: ProgressEvent) {
    main.post { sink?.success(event) }
  }
}
