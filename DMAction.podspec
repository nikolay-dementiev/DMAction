
Pod::Spec.new do |s|
  s.name             = 'DMAction'
  s.version          = '1.1.0'
  s.summary          = 'Action with fallback possibility'
  s.description      = <<-DESC
    Runs completion-based work as an action that can be retried up to N more times after a
    failure, and can fall back to another action. A run calls its producers in order until one
    succeeds, and delivers one result: a success carries the action's attempt plus the
    attempts that failed before it.

    DMButtonAction wraps one producer. fallbackTo(_:) and retry(_:) compose actions into a
    DMActionWithFallback.
                       DESC

  s.homepage         = 'https://github.com/nikolay-dementiev/DMAction'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Mykola Dementiev' => 'nikolas.dementiev@gmail.com' }
  s.ios.deployment_target = "17.0"
  s.watchos.deployment_target = "7.0"
  
  s.source           = { :git => 'https://github.com/nikolay-dementiev/DMAction.git', :tag => s.version.to_s }
  s.source_files = 'Sources/**/*.{swift,h,m,c}'
  s.requires_arc = true
  s.frameworks = 'Foundation'
  
  s.cocoapods_version = '>= 1.4.0'
  if s.respond_to?(:swift_versions) then
    s.swift_versions = ['5.0', '6.0']
  else
    s.swift_version = '5.0'
  end
end
