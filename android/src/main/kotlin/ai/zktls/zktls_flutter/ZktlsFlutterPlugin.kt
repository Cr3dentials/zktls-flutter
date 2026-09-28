package ai.zktls.zktls_flutter

import android.app.Activity
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import ai.zktls.sdk.SdkException
import ai.zktls.sdk.WebViewLoginPresenter
import ai.zktls.sdk.ZktlsClient
import ai.zktls.sdk.Claim as SdkClaim
import ai.zktls.sdk.LoginDisclosure as SdkLoginDisclosure
import ai.zktls.sdk.Phase as SdkPhase
import ai.zktls.sdk.ProofReport as SdkProofReport
import ai.zktls.sdk.SessionConfig as SdkSessionConfig
import ai.zktls.sdk.TypedOutput as SdkTypedOutput

// Implements the Pigeon-generated ZktlsHostApi. One native ZktlsClient per
// session, keyed by a generated sessionId; Dart only ever holds the id. The
// host-api methods are suspend, matching the SDK's own suspend verbs, so Pigeon
// runs them and marshals the result. Progress goes out over the Pigeon event
// channel.
class ZktlsFlutterPlugin : FlutterPlugin, ActivityAware, ZktlsHostApi {
  private val sessions = ConcurrentHashMap<String, ZktlsClient>()
  private val progress = ProgressEmitter()
  private var activity: Activity? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
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

  override suspend fun create(config: SessionConfig): String {
    val client = ZktlsClient(toSdkConfig(config))
    val sessionId = UUID.randomUUID().toString()
    // Registered before the id is returned so no early phase is missed.
    client.onProgress { phase, percent ->
      progress.emit(ProgressEvent(sessionId, toPigeonPhase(phase), percent.toLong()))
    }
    sessions[sessionId] = client
    return sessionId
  }

  override suspend fun login(sessionId: String, disclosure: Disclosure?) = guarded {
    val client = requireSession(sessionId)
    val act = activity ?: throw FlutterError("Internal", "no current activity for the login WebView")
    val presenter = if (disclosure != null) {
      WebViewLoginPresenter(act, disclosure = toSdkDisclosure(disclosure))
    } else {
      WebViewLoginPresenter(act)
    }
    client.login(presenter)
    Unit
  }

  override suspend fun capture(sessionId: String) = guarded {
    requireSession(sessionId).capture()
    Unit
  }

  override suspend fun prove(sessionId: String): ProofReport = guarded {
    toPigeonReport(requireSession(sessionId).prove())
  }

  override suspend fun claim(sessionId: String): Claim = guarded {
    toPigeonClaim(requireSession(sessionId).claim())
  }

  override fun cancel(sessionId: String) {
    sessions[sessionId]?.cancel()
  }

  override suspend fun dispose(sessionId: String) {
    sessions.remove(sessionId)
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
    trustOperatorKey = c.trustOperatorKey,
    policyBundleJson = c.policyBundleJson,
    policyBundleDigest = c.policyBundleDigest,
  )

  private fun toSdkDisclosure(d: Disclosure) = SdkLoginDisclosure(
    title = d.title ?: "",
    message = d.message ?: "",
    accept = d.accept ?: "",
    decline = d.decline ?: "",
  )

  // The SDK's u64/u32 values are unsigned; Pigeon carries them as Long. The
  // magnitudes here (timestamps, byte counts, epoch) sit well inside Long.
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

  private fun toPigeonPhase(p: SdkPhase): Phase = when (p) {
    SdkPhase.loggingIn -> Phase.LOGGING_IN
    SdkPhase.allocating -> Phase.ALLOCATING
    SdkPhase.capturing -> Phase.CAPTURING
    SdkPhase.captured -> Phase.CAPTURED
    SdkPhase.proving -> Phase.PROVING
    SdkPhase.proved -> Phase.PROVED
    SdkPhase.claiming -> Phase.CLAIMING
    SdkPhase.done -> Phase.DONE
    SdkPhase.failed -> Phase.FAILED
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
