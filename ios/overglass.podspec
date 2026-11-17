Pod::Spec.new do |s|
  s.name             = 'overglass'
  s.version          = '0.3.0'
  s.summary          = 'Real iOS system chrome and controls (Liquid Glass) for Flutter: bars hosted beside the FlutterView with no platform views.'
  s.description      = <<-DESC
Real iOS system chrome and controls (Liquid Glass) for Flutter: bars hosted beside the FlutterView with no platform views.
                       DESC
  s.homepage         = 'https://pub.dev/packages/overglass'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'overglass authors'
  s.source           = { :path => '.' }
  s.source_files = 'overglass/Sources/overglass/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  s.resource_bundles = {'overglass_privacy' => ['overglass/Sources/overglass/PrivacyInfo.xcprivacy']}
end
