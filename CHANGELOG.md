## 1.0.0

The first public release, on the zkTLS SDK 1.0.0 (`~> 1.0`).

* The proof flow: `ZktlsClient.create`, then `login`, `capture`, `prove` and `claim`, with
  `onProgress`, `cancel` and `dispose`.
* Platform packs: `ZktlsClient.createTree` and `runTree`, returning the run's `TreeSummary`.
* A session survives the user leaving the app and a Wi-Fi to cellular handover, as the SDK's guides
  ask of a native app: the plugin runs the SDK's lifecycle, and on Android its foreground service.
* A login disclosure field left null keeps the SDK's standard text.
* `sdkErrorCodeOf` reads the `SdkErrorCode` of a verb's `PlatformException`.
* Licensed Apache-2.0.
