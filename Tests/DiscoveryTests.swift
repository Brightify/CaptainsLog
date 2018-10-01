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

import RxSwift
import RxBlocking
import RxNimble

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

                let deviceService = NetService.loggerService(named: "device-name", port: 11111)

                var netService: NetService?
                let browser = DiscoveryServiceBrowser()
                browser.search()
                expect(browser.unresolvedServices.map { $0.first }).first.toNot(beNil())
//                browser.didResolveServices = { services in
//                    for service in services {
//                        netService = service
//                        service.stop()
//                    }
//                }

//                async {
//                }

//                expect(netService).toEventuallyNot(beNil())
            }

            it("connects to device") {
                let originalApplication = DiscoveryHandshake.Application(
                    id: UUID().uuidString,
                    name: "An application",
                    identifier: "org.brightify.CaptainsLogTests",
                    version: "0.1",
                    date: Date())
                let originalLogViewer = DiscoveryHandshake.LogViewer(
                    id: UUID().uuidString,
                    name: "A logger")

                let serverConnector = DiscoveryServerConnector(application: originalApplication)
                let clientConnector = DiscoveryClientConnector(logViewer: originalLogViewer)

                var application: DiscoveryHandshake.Application?
                var logViewer: DiscoveryHandshake.LogViewer?

//                connectionEstablished: { newConnection in
//                    connection = newConnection
//                    newConnection.close()
//                })

                let deviceService = NetService.loggerService(named: "device-name", port: 11111)

                let browser = DiscoveryServiceBrowser()

//                resolvedService: { service in
//                    connector.connect(service: service)
//                })

//                browser.search()

//                let connection = try!

//                expect(connection).toNot(beNil())

                var loggerConnection: LoggerConnection?
                var logViewerConnection: LogViewerConnection?

                _ = async {
                    browser.search()

                    let services = try await(browser.unresolvedServices.skip(1).take(1).asSingle())
                    let connections = try services.map {
                        try await(clientConnector.connect(service: $0, lastLogItemId: .unassigned))
                    }
                    loggerConnection = connections.first
                    loggerConnection?.close()
                }.subscribe()

                _ = async {
                    let stream = try await(deviceService.publish().take(1).asSingle())
                    logViewerConnection = try await(serverConnector.connect(stream: stream))
                    logViewerConnection?.close()
                }.subscribe()

                expect(loggerConnection).toEventuallyNot(beNil())
                expect(logViewerConnection).toEventuallyNot(beNil())

                expect(loggerConnection?.application).toEventually(equal(originalApplication))
                expect(logViewerConnection?.logViewer).toEventually(equal(originalLogViewer))

//                browser.didResolveServices = { services in
//                    for service in services {
//                        async {
//                            connection = try await(connector.connect(service: service))
//                            connection?.close()
//                        }
//                    }
//                }

//                async {
//
//                }.debug("connect")

//                expect(connector).toEventuallyNot(beNil())
//                expect(connection?.inputStream).toEventuallyNot(beNil())
//                expect(connection?.outputStream).toEventuallyNot(beNil())
            }

//            it("sends logged items") {
//                let originalApplication = DiscoveryHandshake.Application(
//                    id: UUID().uuidString,
//                    name: "An application",
//                    identifier: "org.brightify.CaptainsLogTests",
//                    version: "0.1",
//                    date: Date())
//                let originalLogger = DiscoveryHandshake.Logger(
//                    id: UUID().uuidString,
//                    name: "A logger")
//
//                let originalLogItem = LogItem(
//                    id: UUID().uuidString,
//                    kind: LogItem.Kind.request(Request(
//                        method: HTTPMethod.get,
//                        url: URL(fileURLWithPath: "/Test"),
//                        headers: ["HeaderName": "HeaderValue"],
//                        time: Date(),
//                        body: Data(),
//                        response: nil)))
//
//                var application: DiscoveryHandshake.Application?
//                var logItem: LogItem?
//
//                let connector = DiscoveryServiceConnector()
//
//                let log = CaptainsLog(info: originalApplication)
//                let browser = DiscoveryServiceBrowser()
//                browser.didResolveServices = { services in
//                    for service in services {
//                        print("xxx:", service)
//                        async {
//                            let connection = try await(connector.connect(service: service))
//                            print("Connection:", connection)
//                            connection.open()
//
//                            application = try await(DiscoveryHandshake().perform(on: connection, for: originalLogger))
//                            print("Application:", application)
//                            logItem = try connection.inputStream.decode(LogItem.self)
//
//                            print("LogItem:", logItem)
//                            connection.close()
//                        }
//                    }
//
//                }
//
//                async {
//                    log.log(item: originalLogItem)
//
//                    browser.search()
//                }
//
//                expect(connector).toEventuallyNot(beNil())
//                expect(application).toEventuallyNot(beNil())
//                expect(logItem).toEventuallyNot(beNil())
//
//                expect(application).toEventually(equal(originalApplication))
//                expect(logItem).toEventually(equal(originalLogItem))
//            }
        }
    }
}
