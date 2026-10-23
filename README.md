# zktls-flutter

Flutter bridge for the [zkTLS native SDK](https://github.com/Cr3dentials/zktls-sdk). It exposes the
SDK's API to a Flutter app: the native SDK does the cryptography, this plugin is the thin bridge
that lets Dart drive it. One API on both platforms, generated with
[Pigeon](https://pub.dev/packages/pigeon) from `pigeons/messages.dart`.

## Install

Not on pub.dev yet:

```yaml
dependencies:
  zktls_flutter:
    git: https://github.com/Cr3dentials/zktls-flutter.git
```

Android minSdk 24, iOS 15+. The Android app currently builds with JDK 17; iOS needs Xcode.

## The native SDK

The bridge links the compiled SDK, not its source: `xyz.cr3dentials:zktls-sdk:1.0.0` from Maven Central
for Android, and the `ZktlsSDK` pod from [zktls-sdk-releases](https://github.com/Cr3dentials/zktls-sdk-releases)
for iOS. That repository is its own CocoaPods spec source, so an app's `Podfile` lists it first:

```ruby
source 'https://github.com/Cr3dentials/zktls-sdk-releases.git'
source 'https://cdn.cocoapods.org/'
```

## Proving a fact

`ZktlsClient` mirrors the SDK's facade: `create`, `login`, `capture`, `prove`, `claim`, `onProgress`,
`cancel`, `dispose`. `create` takes a `SessionConfig` (baseUrl, appCredential, the trust and policy
bundles and their pins, an idempotencyKey new for every session) and returns a client keyed by a
session id; the opaque handles never cross the bridge, and login runs the SDK's native WebView.

```dart
final client = await ZktlsClient.create(config);
final progress = client.onProgress().listen((e) => print('${e.phase} ${e.percent}'));
try {
  await client.login();
  await client.capture();
  final report = await client.prove();
  if (report.accepted) {
    final claim = await client.claim(); // your backend verifies claim.encoded again
  }
} finally {
  await progress.cancel();
  await client.dispose();
}
```

A failed verb throws a `PlatformException` whose `code` is an `SdkErrorCode`; `Transport` and `Policy`
carry text. The SDK never retries, and neither should the app.

On Android a session shows the SDK's foreground-service notification while it is protected: from
`login` to the end of the proof, and while a pack's run is with the attester. Its text and icon are the
SDK's resources, which an app can override.

## Platform packs

`ZktlsClient.createTree()` makes a client for platform-pack runs, and `runTree` takes a
`TreeRunConfig` (the run's platformId, plus the result URL and token your backend issued for it) and a
`TreeDisclosure`. The SDK shows the disclosure, opens the platform's pages and posts the data to the
result URL; the app gets a `TreeSummary` with counts only. `cancel` and `dispose` work as for a proof
session. A tree client has no `SessionConfig`, so the proof verbs on it fail.

```dart
final client = await ZktlsClient.createTree();
try {
  final summary = await client.runTree(config, disclosure);
  print(summary.succeeded ? 'Collected' : 'Not collected: ${summary.error}');
} finally {
  await client.dispose();
}
```

Both bridges are verified against the real SDK: the round-trips run on an Android device and an iOS
simulator. `example/` is a runnable harness whose "Test bridge" button exercises the round-trips that
need no live backend. Its "Run a platform pack" button runs a pack against a local pack-lab once
`example/lib/lab_settings.dart` is filled from pack-lab's `tree.json`.
