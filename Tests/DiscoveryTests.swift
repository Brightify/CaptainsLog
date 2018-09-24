//
//  CaptainsLog_iOSTests.swift
//  CaptainsLog-iOSTests
//
//  Created by Tadeas Kriz on 22/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import XCTest
#if os(iOS)
@testable import CaptainsLog_iOS
#elseif os(macOS)
@testable import CaptainsLog_macOS
#elseif os(tvOS)
@testable import CaptainsLog_tvOS
#endif

import Quick
import Nimble

class DiscoverySpec: QuickSpec {
    override func spec() {
        describe("the 'Discovery' workflow") {
            beforeSuite {
                AsyncDefaults.Timeout = 10
                AsyncDefaults.PollInterval = 0.1
            }
            afterSuite {
                AsyncDefaults.Timeout = 1
                AsyncDefaults.PollInterval = 0.01
            }

            it("finds logger") {
                let loggerService = DiscoveryLoggerService(id: "some-id")
                var urls: [URL]?

                let client = DiscoveryClient(loggerFound: { loggerUrls in
                    urls = loggerUrls
                    print(loggerUrls)
                })

                loggerService.publish()

                client.search()

                expect(urls).toEventuallyNot(beNil())
                expect(urls?.count).toEventually(beGreaterThan(0))
            }
        }
    }
}
