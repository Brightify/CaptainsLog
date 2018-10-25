inhibit_all_warnings!

abstract_target 'CaptainsLog' do
    use_frameworks!

    pod 'Fetcher', :git => 'https://github.com/Brightify/Fetcher.git', :branch => 'fix/xcode10', :subspecs => ['Core']
    pod 'SwiftyBeaver'
    pod 'CocoaLumberjack/Swift'
    # TODO Remove
    pod 'RxSwift'

    target 'CaptainsLog-macOS'
    target 'CaptainsLog-iOS'
#    target 'CaptainsLog-tvOS'

    abstract_target 'Tests' do
#        inherit! :search_paths

        target 'CaptainsLog-macOSTests'
        target 'CaptainsLog-iOSTests'
#        target 'CaptainsLog-tvOSTests'

        pod 'RxBlocking'
        pod 'RxNimble'

        pod 'Quick'
        pod 'Nimble'
    end
end
