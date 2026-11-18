## 2.0.0

The first public release, on the zkTLS SDK 2.2.0 or later within 2.x. Version 2 of the plugin wraps
version 2 of the SDK. Published as `cr3dentials_zktls`; `zktls_flutter` is discontinued.

* `Zktls.configure(appKey, theme:, strings:)` once, then `Zktls.verify(platforms, reference)` or
  `Zktls.verifyToken(token)` per user, returning a `VerifyOutcome`. The theme is a `ZktlsTheme`, the
  native SDK's name, which does not clash with Material's `Theme`: colors are exactly `#RRGGBB` or
  `#AARRGGBB`, and the logo an image's name in the app.
* The `refused` error code, with the reason from `refusalOf`.
* The `invalidArgument` error code (`InvalidArgument`): `configure` given a color in another form throws it on
  both platforms and changes nothing.
* The proof flow: `ZktlsClient.create`, then `login`, `capture`, `prove` and `claim`, with
  `onProgress`, `cancel` and `dispose`. A proof session survives the user leaving the app and a Wi-Fi to
  cellular handover: the plugin runs the SDK's lifecycle, and on Android its foreground service.
* A login disclosure field left null keeps the SDK's standard text.
* `sdkErrorCodeOf` reads the `SdkErrorCode` of a call's `PlatformException`.
* Licensed Apache-2.0.
