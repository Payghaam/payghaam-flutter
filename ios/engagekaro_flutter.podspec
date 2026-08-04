Pod::Spec.new do |s|
  s.name             = 'engagekaro_flutter'
  s.version          = '0.1.0'
  s.summary          = 'EngageKaro Flutter SDK — iOS APNs integration.'
  s.description      = 'Native iOS push (APNs) registration and notification handling for the EngageKaro Flutter SDK.'
  s.homepage         = 'https://github.com/msamoeed/engagekaro'
  s.license          = { :type => 'MIT' }
  s.author           = { 'EngageKaro' => 'dev@engagekaro.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'engagekaro_flutter/Sources/engagekaro_flutter/**/*.swift'
  s.dependency 'Flutter'
  # Canonical native SDK (sdks/ios) — see sdk-native-wrapper-design.md. Resolved
  # via a local `pod 'EngageKaro', :path => ...` entry in the consuming app's
  # Podfile, the CocoaPods equivalent of the Gradle composite build used on
  # Android.
  s.dependency 'EngageKaro'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
