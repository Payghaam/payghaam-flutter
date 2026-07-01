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
  s.platform         = :ios, '12.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
