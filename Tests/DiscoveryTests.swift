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
                AsyncDefaults.Timeout = 20
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

                let deviceService = DiscoveryService(name: "device-name", port: 11111)

                var netService: NetService?
                let browser = DiscoveryServiceBrowser()
                browser.didResolveServices = { services in
                    for service in services {
                        netService = service
                        service.stop()
                    }
                }

                async {
                    browser.search()
                }

                expect(netService).toEventuallyNot(beNil())
            }

            it("connects to device") {
                var connection: DiscoveryConnection?

                let connector = DiscoveryServiceConnector()

//                connectionEstablished: { newConnection in
//                    connection = newConnection
//                    newConnection.close()
//                })

                let deviceService = DiscoveryService(name: "device-name", port: 11111)

                let browser = DiscoveryServiceBrowser()

//                resolvedService: { service in
//                    connector.connect(service: service)
//                })
                browser.didResolveServices = { services in
                    for service in services {
                        async {
                            connection = try await(connector.connect(service: service))
                            connection?.close()
                        }
                    }
                }

                async {
                    browser.search()
                }.debug("connect")

                expect(connector).toEventuallyNot(beNil())
                expect(connection?.inputStream).toEventuallyNot(beNil())
                expect(connection?.outputStream).toEventuallyNot(beNil())
            }

            it("handshakes with device") {
                let originalApplication = DiscoveryHandshake.Application(
                    id: UUID().uuidString,
                    name: "An application",
                    identifier: "org.brightify.CaptainsLogTests",
                    version: "0.1",
                    date: Date())
                let originalLogger = DiscoveryHandshake.Logger(
                    id: UUID().uuidString,
                    name: "A logger")

                var application: DiscoveryHandshake.Application?
                var logger: DiscoveryHandshake.Logger?

                let connector = DiscoveryServiceConnector()

//                connectionEstablished: { applicationConnection in
//                    async {
//                        applicationConnection.open()
//                        application = try await(DiscoveryHandshake().perform(on: applicationConnection, for: originalLogger))
//                        print("Application:", application)
//                        applicationConnection.close()
//                    }
//                })

                let deviceService = DiscoveryService(name: "device-name", port: 11111)

                let browser = DiscoveryServiceBrowser() //resolvedService: connector.connect(service:))
                browser.didResolveServices = { services in
                    for service in services {
                        async {
                            let connection = try await(connector.connect(service: service))
                            connection.open()
                            application = try await(DiscoveryHandshake().perform(on: connection, for: originalLogger))
                            print("Application:", application)
                            connection.close()
                        }
                    }
                }

                async {
                    browser.search()

                    let connection = try await(deviceService.acceptConnection())
                    connection.open()
                    logger = try await(DiscoveryHandshake().perform(on: connection, for: originalApplication))
                    print("Logger:", logger)
                    connection.close()
                }

                expect(connector).toEventuallyNot(beNil())
                expect(application).toEventuallyNot(beNil())
                expect(logger).toEventuallyNot(beNil())

                expect(application).toEventually(equal(originalApplication))
                expect(logger).toEventually(equal(originalLogger))
            }

            it("sends logged items") {
                let originalApplication = DiscoveryHandshake.Application(
                    id: UUID().uuidString,
                    name: "An application",
                    identifier: "org.brightify.CaptainsLogTests",
                    version: "0.1",
                    date: Date())
                let originalLogger = DiscoveryHandshake.Logger(
                    id: UUID().uuidString,
                    name: "A logger")

                let originalLogItem = LogItem(
                    id: UUID().uuidString,
                    kind: LogItem.Kind.request(Request(
                        method: HTTPMethod.get,
                        url: URL(fileURLWithPath: "/Test"),
                        headers: ["HeaderName": "HeaderValue"],
                        time: Date(),
                        body: Data(),
                        response: nil)))

                var application: DiscoveryHandshake.Application?
                var logItem: LogItem?

                let connector = DiscoveryServiceConnector()

                let log = CaptainsLog(info: originalApplication)
                let browser = DiscoveryServiceBrowser()
                browser.didResolveServices = { services in
                    for service in services {
                        print("xxx:", service)
                        async {
                            let connection = try await(connector.connect(service: service))
                            print("Connection:", connection)
                            connection.open()

                            application = try await(DiscoveryHandshake().perform(on: connection, for: originalLogger))
                            print("Application:", application)
                            logItem = try connection.inputStream.decode(LogItem.self)

                            print("LogItem:", logItem)
                            connection.close()
                        }
                    }

                }

                async {
                    log.log(item: originalLogItem)

                    browser.search()
                }

                expect(connector).toEventuallyNot(beNil())
                expect(application).toEventuallyNot(beNil())
                expect(logItem).toEventuallyNot(beNil())

                expect(application).toEventually(equal(originalApplication))
                expect(logItem).toEventually(equal(originalLogItem))
            }
        }
    }
}
