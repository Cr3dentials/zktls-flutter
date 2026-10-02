# zktls-flutter

Flutter bridge for the [zkTLS native SDK](https://github.com/Cr3dentials/zktls-sdk). It exposes the
SDK's six verbs to a Flutter app: the native SDK does the cryptography, this plugin is the thin bridge
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

The bridge links the compiled SDK, not its source, and consumes it from a local build until it is
published. Build it from [Cr3dentials/zktls-sdk](https://github.com/Cr3dentials/zktls-sdk):
`:sdk:publishReleasePublicationToMavenLocal` puts the AAR in the local Maven cache, which the plugin
resolves as `io.github.cr3dentials:zktls-sdk` through `mavenLocal()`; `build-ios.sh` produces the
Swift package the app's Podfile points at as a local `ZktlsSDK` pod. Switch to the published
coordinate once it lands, with no bridge change.

## The six verbs

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

Both bridges are verified against the real SDK: the round-trips run on an Android device and an iOS
simulator. `example/` is a runnable harness whose "Test bridge" button exercises the round-trips that
need no live backend.
