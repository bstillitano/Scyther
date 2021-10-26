Pod::Spec.new do |s|
  s.name             = 'Scyther'
  s.version          = '1.2.2'
  s.summary          = 'Just like scyther, this menu helps you cut through bugs in your iOS app.'

  s.homepage         = 'https://github.com/bstillitano/Scyther'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Brandon Stillitano' => 'b.stillitano95@gmail.com' }
  s.source           = { :git => 'https://github.com/bstillitano/Scyther.git', :tag => s.version.to_s }

  s.ios.deployment_target = '11.0'
  s.swift_version = '5.0'

  s.source_files = 'Sources/Scyther/**/*'
  s.resources = "Sources/Scyther/**/*.{gpx,xml}"
  
  s.dependency 'SnapKit', '~> 5.0.1'
end
