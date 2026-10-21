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
import ai.zktls.sdk.TreeWebViewHost
import ai.zktls.sdk.WebViewLoginPresenter
import ai.zktls.sdk.ZktlsClient
import ai.zktls.sdk.Claim as SdkClaim
import ai.zktls.sdk.LoginDisclosure as SdkLoginDisclosure
import ai.zktls.sdk.Phase as SdkPhase
import ai.zktls.sdk.ProofReport as SdkProofReport
import ai.zktls.sdk.SessionConfig as SdkSessionConfig
import ai.zktls.sdk.SourceEvidence as SdkSourceEvidence
import ai.zktls.sdk.TreeDisclosure as SdkTreeDisclosure
import ai.zktls.sdk.TreeRunConfig as SdkTreeRunConfig
import ai.zktls.sdk.TreeSource as SdkTreeSource
import ai.zktls.sdk.TreeSummary as SdkTreeSummary
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

  override suspend fun create(config: SessionConfig): String =
    register(ZktlsClient(toSdkConfig(config)))

  override suspend fun createTree(): String = register(ZktlsClient())

  private fun register(client: ZktlsClient): String {
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
      WebViewLoginPresenter(act) { toSdkDisclosure(disclosure) }
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

  override suspend fun runTree(
    sessionId: String,
    config: TreeRunConfig,
    disclosure: TreeDisclosure,
  ): TreeSummary = guarded {
    val client = requireSession(sessionId)
    val act = activity ?: throw FlutterError("Internal", "no current activity for the tree WebView")
    val host = TreeWebViewHost(act, toSdkTreeDisclosure(disclosure))
    toPigeonSummary(client.runTree(toSdkTreeConfig(config), host))
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
    trustBundleUrl = c.trustBundleUrl ?: "",
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

  private fun toSdkTreeConfig(c: TreeRunConfig) = SdkTreeRunConfig(
    baseUrl = c.baseUrl,
    appCredential = c.appCredential,
    userIdHash = c.userIdHash,
    idempotencyKey = c.idempotencyKey,
    clientRegion = c.clientRegion,
    networkKey = c.networkKey,
    platformId = c.platformId,
    trustBundleJson = c.trustBundleJson,
    trustBundleUrl = c.trustBundleUrl ?: "",
    trustOperatorKey = c.trustOperatorKey,
    policyBundleJson = c.policyBundleJson,
    policyBundleDigest = c.policyBundleDigest,
    relyingPartyNonceHex = c.relyingPartyNonceHex,
    resultUrl = c.resultUrl,
    resultToken = c.resultToken,
    paramsJson = c.paramsJson,
  )

  private fun toSdkTreeDisclosure(d: TreeDisclosure) = SdkTreeDisclosure(
    title = d.title,
    message = d.message,
    accept = d.accept,
    decline = d.decline,
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

  private fun toPigeonSummary(s: SdkTreeSummary) = TreeSummary(
    succeeded = s.succeeded,
    error = s.error,
    sources = s.sources.map(::toPigeonSource),
    claim = s.claim?.let(::toPigeonClaim),
    apiCalls = s.apiCalls.toLong(),
    durationMs = s.durationMs.toLong(),
    delivered = s.delivered,
    deliveryError = s.deliveryError,
    resultBytes = s.resultBytes.toLong(),
    isolation = s.isolation,
    handedOff = s.handedOff,
  )

  private fun toPigeonSource(s: SdkTreeSource) = TreeSource(
    storeAs = s.storeAs,
    evidence = when (s.evidence) {
      SdkSourceEvidence.OBSERVED -> SourceEvidence.OBSERVED
      SdkSourceEvidence.ATTESTED -> SourceEvidence.ATTESTED
    },
    rows = s.rows.toLong(),
    pages = s.pages.toLong(),
    bytes = s.bytes.toLong(),
    complete = s.complete,
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
