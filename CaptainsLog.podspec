#
#  Be sure to run `pod spec lint CaptainsLog.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see https://docs.cocoapods.org/specification.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |spec|
  spec.name         = "CaptainsLog"
  spec.version      = "0.0.1"
  spec.summary      = "Lorem ipsum dolor sit amet."
  spec.description  = <<-DESC
                      Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Fusce nibh. Integer malesuada. Aliquam ornare wisi eu metus.
                      DESC
  spec.homepage     = "https://www.reactant.tech"
  spec.license      = "MIT"
  spec.author       = { 
    'Tadeas Kriz' => 'tadeas@brightify.org',
    'Robin Krenecky' => 'rkrenecky@gmail.com' 
  }
  spec.source       = { 
    :git => "https://github.com/Brightify/CaptainsLog.git",
    :tag => spec.version.to_s
   }
  spec.swift_version = "4.2"
  spec.ios.deployment_target = "10.3"
  spec.osx.deployment_target = "10.13"
  spec.default_subspec = 'Models', 'Discovery', 'Core', 'NSURLSession'

  spec.subspec 'Models' do |subspec|
    subspec.source_files = [
      'Sources/Models/**/*.swift'
    ]
  end

  spec.subspec 'Discovery' do |subspec|
    subspec.dependency 'CaptainsLog/Models'
    subspec.source_files = [
      'Sources/Discovery/**/*.swift'
    ]
  end

  spec.subspec 'Core' do |subspec|
    subspec.dependency 'CaptainsLog/Discovery'
    subspec.source_files = [ 
      'Sources/Core/**/*.swift'
    ]
  end

  spec.subspec 'Fetcher' do |subspec|
    subspec.dependency 'CaptainsLog/Core'
    subspec.dependency 'Fetcher/Core'
    subspec.source_files = [
      'Sources/Fetcher/**/*.swift'
    ]
  end

  spec.subspec 'SwiftyBeaver' do |subspec|
    subspec.dependency 'CaptainsLog/Core'
    subspec.dependency 'SwiftyBeaver'
    subspec.source_files = [
      'Sources/SwiftyBeaver/**/*.swift'
    ]
  end

  spec.subspec 'NSURLSession' do |subspec|
    subspec.dependency 'CaptainsLog/Core'
    subspec.source_files = [
      'Sources/NSURLSession/**/*.swift'
    ]
  end

  spec.subspec 'CocoaLumberjack' do |subspec|
    subspec.dependency 'CaptainsLog/Core'
    subspec.dependency 'CocoaLumberjack/Swift'
    subspec.source_files = [
      'Sources/CocoaLumberjack/**/*.swift'
    ]
  end
end
