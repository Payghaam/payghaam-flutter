Pod::Spec.new do |s|
  s.name             = 'payghaam_flutter'
  s.version          = '0.1.2'
  s.summary          = 'Payghaam Flutter SDK — iOS APNs integration.'
  s.description      = 'Native iOS push (APNs) registration and notification handling for the Payghaam Flutter SDK.'
  s.homepage         = 'https://github.com/payghaam/payghaam-flutter'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Payghaam' => 'dev@payghaam.com' }
  s.source           = { :git => 'https://github.com/payghaam/payghaam-flutter.git', :tag => s.version.to_s }
  s.source_files     = 'payghaam_flutter/Sources/payghaam_flutter/**/*.swift'
  s.dependency 'Flutter'
  # Canonical native SDK, published to the CocoaPods trunk as the `Payghaam`
  # pod. Pinned so a native SDK fix ships only when this repo bumps it.
  # Live Activities (`PayghaamLiveActivities`, push-wake refresh) ship in 0.1.4+.
  s.dependency 'Payghaam', '>= 0.1.4'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
