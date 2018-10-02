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
        Hooks.recordCallStackOnError = true

        describe("the 'Discovery' workflow") {
            beforeSuite {
                AsyncDefaults.Timeout = 20
                AsyncDefaults.PollInterval = 0.1
            }
            afterSuite {
                AsyncDefaults.Timeout = 1
                AsyncDefaults.PollInterval = 0.01
            }

            let mockApplication = DiscoveryHandshake.Application(
                id: UUID().uuidString,
                name: "An application",
                identifier: "org.brightify.CaptainsLogTests",
                version: "0.1",
                date: Date())
            let mockLogViewer = DiscoveryHandshake.LogViewer(
                id: UUID().uuidString,
                name: "A logger")

            let mockLogItem1 = LogItem(
                id: UUID().uuidString,
                kind: LogItem.Kind.request(Request(
                    method: HTTPMethod.get,
                    url: URL(fileURLWithPath: "/Test1"),
                    headers: ["HeaderName1": "HeaderValue1"],
                    time: Date(),
                    body: Data(),
                    response: nil)))

            let mockLogItem2 = LogItem(
                id: UUID().uuidString,
                kind: LogItem.Kind.request(Request(
                    method: HTTPMethod.get,
                    url: URL(fileURLWithPath: "/Test2"),
                    headers: ["HeaderName2": "HeaderValue2"],
                    time: Date(),
                    body: Data(),
                    response: nil)))

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
            }

            it("connects to device") {
                let serverConnector = DiscoveryServerConnector(application: mockApplication)
                let clientConnector = DiscoveryClientConnector(logViewer: mockLogViewer)

                let deviceService = NetService.loggerService(named: "device-name", port: 11111)

                let browser = DiscoveryServiceBrowser()

                var loggerConnection: LoggerConnection?
                var logViewerConnection: LogViewerConnection?

                _ = async {
                    browser.search()

                    let services = try await(browser.unresolvedServices.skip(1).take(1).asSingle())
                    let connections = try services.map {
                        try await(clientConnector.connect(service: $0, lastLogItemId: { _ in .unassigned }))
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

                expect(loggerConnection?.application).toEventually(equal(mockApplication))
                expect(logViewerConnection?.logViewer).toEventually(equal(mockLogViewer))
            }

            it("sends logged items") {
                var logItem: LogItem?
                var loggerConnection: LoggerConnection?

                let clientConnector = DiscoveryClientConnector(logViewer: mockLogViewer)

                let log = CaptainsLog(info: mockApplication)
                let browser = DiscoveryServiceBrowser()

                _ = async {
                    browser.search()

                    let services = try await(browser.unresolvedServices.skip(1).take(1).asSingle())
                    let connections = try services.map {
                        try await(clientConnector.connect(service: $0, lastLogItemId: { _ in .unassigned }))
                    }
                    loggerConnection = connections.first

                    logItem = try loggerConnection?.stream.input.readDecodable(LogItem.self)

                    loggerConnection?.close()
                    }.subscribe()

                _ = async {
                    log.log(item: mockLogItem1)
                }.subscribe()

                expect(loggerConnection).toEventuallyNot(beNil())
                expect(logItem).toEventuallyNot(beNil())

                expect(loggerConnection?.application).toEventually(equal(mockApplication))
                expect(logItem).toEventually(equal(mockLogItem1))
            }

            it("reconnects on connection closed") {
                var logItem1: LogItem?
                var logItem2: LogItem?

                let server = CaptainsLogServer(logViewer: mockLogViewer)
                let log = CaptainsLog(info: mockApplication)

                _ = async(on: DispatchQueue(label: "LogViewer")) {
                    server.startSearching()

                    logItem1 = try server.itemReceived.toBlocking().first()?.item
                    logItem2 = try server.itemReceived.toBlocking().first()?.item
                }.subscribe()

                _ = async(on: DispatchQueue(label: "Logger")) {
                    Thread.sleep(forTimeInterval: 2)

                    log.log(item: mockLogItem1)

                    Thread.sleep(forTimeInterval: 0.1)

                    log.disconnectAll()

                    Thread.sleep(forTimeInterval: 0.1)

                    log.log(item: mockLogItem2)
                }.subscribe()

                expect(logItem1).toEventuallyNot(beNil())
                expect(logItem2).toEventuallyNot(beNil())

                expect(logItem1).toEventually(equal(mockLogItem1))
                expect(logItem2).toEventually(equal(mockLogItem2))
            }

            it("reconnects on connection closed and republish") {
                var logItem1: LogItem?
                var logItem2: LogItem?

                let server = CaptainsLogServer(logViewer: mockLogViewer)
                let log = CaptainsLog(info: mockApplication)

                _ = async(on: DispatchQueue(label: "LogViewer")) {
                    server.startSearching()

                    logItem1 = try server.itemReceived.debug("item1 received").toBlocking().first()?.item
                    logItem2 = try server.itemReceived.debug("item2 received").toBlocking().first()?.item

                }.subscribe()

                _ = async(on: DispatchQueue(label: "Logger")) {
                    log.log(item: mockLogItem1)

                    log.simulateDisconnect(timeBetweenReconnect: 2)

                    log.log(item: mockLogItem2)
                }.subscribe()

                expect(logItem1).toEventuallyNot(beNil())
                expect(logItem2).toEventuallyNot(beNil())

                expect(logItem1).toEventually(equal(mockLogItem1))
                expect(logItem2).toEventually(equal(mockLogItem2))
            }
        }
    }
}
