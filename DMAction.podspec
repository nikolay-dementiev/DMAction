
Pod::Spec.new do |s|
  s.name             = 'DMAction'
  s.version          = '1.0.1'
  s.summary          = 'Action with fallback possibility'
  s.description      = <<-DESC
    This package allows executing any action block with a retry mechanism (up to N attempts)
    in case the original action fails. If any attempt succeeds, the execution stops immediately,
    and the successful result is returned.

    The original action can be wrapped inside a DMButtonAction object, while the fallback action
    can be encapsulated within a DMActionWithFallback object.
                       DESC

  s.homepage         = 'https://github.com/nikolay-dementiev/DMErrorHandling'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Nikolay Dementiev' => 'nikolas.dementiev@gmail.com' }
  s.ios.deployment_target = "17.0"
  s.watchos.deployment_target = "7.0"
  
  s.source           = { :git => 'https://github.com/nikolay-dementiev/DMAction.git', :tag => "v#{s.version}" }
  s.source_files = 'Sources/**/*.{swift,h,m,c}'
  s.exclude_files = 'Examples/**'
  s.weak_framework = "XCTest"
  s.requires_arc = true
  
  s.cocoapods_version = '>= 1.4.0'
  if s.respond_to?(:swift_versions) then
    s.swift_versions = ['5.0']
  else
    s.swift_version = '5.0'
  end
end
