// Settings for "Run a platform pack". For a local lab, fill these from
// pack-lab's tree.json (base_url, app_credential, user_id_hash, client_region,
// trust_operator_key, runs_url, platforms). Never commit real values.
class LabSettings {
  const LabSettings({
    required this.baseUrl,
    required this.appCredential,
    required this.userIdHash,
    required this.clientRegion,
    required this.trustOperatorKey,
    required this.runsUrl,
    required this.platforms,
    required this.trustBundleUrl,
    required this.policyBundleUrl,
    required this.policyBundleDigest,
  });

  final String baseUrl;
  final String appCredential;
  final String userIdHash;
  final String clientRegion;
  final String trustOperatorKey;
  // Your backend's endpoint that issues each run's result URL and token.
  final String runsUrl;
  final List<String> platforms;
  // Read only for a pack that attests; leave empty otherwise.
  final String trustBundleUrl;
  final String policyBundleUrl;
  final String policyBundleDigest;
}

const labSettings = LabSettings(
  baseUrl: '',
  appCredential: '',
  userIdHash: '',
  clientRegion: '',
  trustOperatorKey: '',
  runsUrl: '',
  platforms: [],
  trustBundleUrl: '',
  policyBundleUrl: '',
  policyBundleDigest: '',
);
