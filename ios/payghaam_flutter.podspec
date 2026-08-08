Pod::Spec.new do |s|
  s.name             = 'payghaam_flutter'
  s.version          = '0.1.0'
  s.summary          = 'Payghaam Flutter SDK — iOS APNs integration.'
  s.description      = 'Native iOS push (APNs) registration and notification handling for the Payghaam Flutter SDK.'
  s.homepage         = 'https://github.com/msamoeed/engagekaro'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Payghaam' => 'dev@payghaam.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'payghaam_flutter/Sources/payghaam_flutter/**/*.swift'
  s.dependency 'Flutter'
  # Canonical native SDK (sdks/ios) — see sdk-native-wrapper-design.md. Resolved
  # via a local `pod 'Payghaam', :path => ...` entry in the consuming app's
  # Podfile, the CocoaPods equivalent of the Gradle composite build used on
  # Android.
  s.dependency 'Payghaam'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
