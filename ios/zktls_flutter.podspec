#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint zktls_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'zktls_flutter'
  s.version          = '1.0.0'
  s.summary          = 'Flutter bridge for the zkTLS native SDK.'
  s.description      = <<-DESC
Proves facts from a user's own account and runs platform packs, over the zkTLS native SDK.
                       DESC
  s.homepage         = 'https://github.com/Cr3dentials/zktls-flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Cr3dentials' => 'https://github.com/Cr3dentials' }
  s.source           = { :path => '.' }
  s.source_files = 'zktls_flutter/Sources/zktls_flutter/**/*'
  s.dependency 'Flutter'
  # The native zkTLS SDK, from the releases repo's pod: the app's Podfile lists
  # https://github.com/Cr3dentials/zktls-sdk-releases.git as a source.
  s.dependency 'ZktlsSDK', '~> 1.0'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'zktls_flutter_privacy' => ['zktls_flutter/Sources/zktls_flutter/PrivacyInfo.xcprivacy']}
end
