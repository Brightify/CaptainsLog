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

            it("finds device") {
                /*
                 Test decription:

                 1. Publish NetService on device
                 2. Run NetServiceBrowser search
                 3. Connect to found services
                 4. Receive logger url from search
                */


                let deviceService = DiscoveryService(name: "device-name", id: "device-id")

//                var urls: [URL]?
                var netService: NetService?

//                let client = DiscoveryServiceBrowser(loggerFound: { loggerUrls in
//                    urls = loggerUrls
//                    print(loggerUrls)
//                })

                let browser = DiscoveryServiceBrowser(resolvedService: { service in
                    netService = service
                })

                deviceService.publish()

                browser.search()

//                expect(urls).toEventuallyNot(beNil())
//                expect(urls?.count).toEventually(beGreaterThan(0))

                expect(netService).toEventuallyNot(beNil())
            }

            fit("sends connection info to device") {
                var connector: DiscoveryServiceConnector?
                let deviceService = DiscoveryService(name: "device-name", id: "device-id")
                let browser = DiscoveryServiceBrowser(resolvedService: { service in
                    connector = DiscoveryServiceConnector(service: service)

                    connector?.connect()
                })

                deviceService.publish()
                browser.search()

                expect(connector).toEventuallyNot(beNil())
                expect(connector?.connection.inputStream).toEventuallyNot(beNil())
                expect(connector?.connection.outputStream).toEventuallyNot(beNil())
                expect { connector?.sent }.toEventually(beGreaterThan(0))
            }
        }
    }
}
