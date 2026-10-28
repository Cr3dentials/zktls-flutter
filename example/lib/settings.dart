// The example's settings. appKey is your app's publishable key from Cr3dentials,
// passed when you run the example so a key never lands in source:
//   flutter run --dart-define=ZKTLS_APP_KEY=zk_test_...
// A zk_test_ key runs only the demo platform, zktls-demo (any user name, the
// password demo), and works on simulators and emulators.
const settings = (appKey: String.fromEnvironment('ZKTLS_APP_KEY'), platforms: ['zktls-demo']);
