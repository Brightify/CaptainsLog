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

final class TestIdentityProvider: IdentityProvider {
    private var identities: [String: ImportedIdentity] = [:]

    func identity(forId identifier: String) -> SecIdentity? {
        return identities[identifier]?.identity
    }

    func load(url: URL, password: String) throws {
        let data = try Data(contentsOf: url)
        let identities = try ImportedIdentity.identities(inP12: data, password: password)

        for identity in identities {
            self.identities[identity.id] = identity
        }
    }
}

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

            // This let's us disambiguate between multiple running tests
            let testIdentifier = UUID().uuidString.prefix(8)
            let serviceType = "_captainslog-transmitter-tests-\(testIdentifier)._tcp."
            let serviceDomain = Constants.domain
            let servicePort = 11123
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

            let publicCertificatePath = Bundle(for: DiscoverySpec.self).url(forResource: "CaptainsLogTestCertificate", withExtension: "cer")!
            let publicCertificateData = try! Data(contentsOf: publicCertificatePath)
            let publicCertificate = SecCertificateCreateWithData(nil, publicCertificateData as CFData)!

            var commonName: CFString?
            assert(SecCertificateCopyCommonName(publicCertificate, &commonName) == noErr)

            let privateKeyURL = Bundle(for: DiscoverySpec.self).url(forResource: "CaptainsLogTestPrivateKey", withExtension: "p12")!
            let identityProvider = TestIdentityProvider()
            try! identityProvider.load(url: privateKeyURL, password: "capitan")

            it("finds device") {
                /*
                 Test decription:

                 1. Publish NetService on device
                 2. Run NetServiceBrowser search
                 3. Connect to found services
                 4. Receive logger url from search
                 */

                let deviceService = NetService.loggerService(
                    named: "finds device",
                    identifier: "ec3f282e-de95-4cdf-a692-66608dc92c05",
                    domain: serviceDomain,
                    type: serviceType,
                    port: servicePort)

                let browser = DiscoveryServiceBrowser(serviceType: serviceType, serviceDomain: serviceDomain)
                browser.search()
                expect(browser.unresolvedServices.map { $0.first }).first.toNot(beNil())
            }

            it("connects to device") {
                let serverConnector = DiscoveryLoggerConnector(application: mockApplication, certificate: publicCertificate)
                let clientConnector = DiscoveryLogViewerConnector(logViewer: mockLogViewer, identityProvider: identityProvider)

                let deviceService = NetService.loggerService(
                    named: "connects to device",
                    identifier: "ec3f282e-de95-4cdf-a692-66608dc92c05",
                    domain: serviceDomain,
                    type: serviceType,
                    port: servicePort)

                let browser = DiscoveryServiceBrowser(serviceType: serviceType, serviceDomain: serviceDomain)

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

                let clientConnector = DiscoveryLogViewerConnector(logViewer: mockLogViewer, identityProvider: identityProvider)

                let logConfiguration = CaptainsLog.Configuration(
                    application: mockApplication,
                    service: CaptainsLog.Configuration.Service(
                        domain: serviceDomain,
                        type: serviceType,
                        port: servicePort),
                    seed: CaptainsLog.Configuration.Seed(
                        commonName: commonName! as String,
                        certificate: publicCertificate))
                let log = CaptainsLog(configuration: logConfiguration)
                let browser = DiscoveryServiceBrowser(serviceType: serviceType, serviceDomain: serviceDomain)

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

                let serverConfiguration = CaptainsLogServer.Configuration(
                    logViewer: mockLogViewer,
                    serviceDomain: serviceDomain,
                    serviceType: serviceType)
                let server = CaptainsLogServer(configuration: serverConfiguration, identityProvider: identityProvider)

                let logConfiguration = CaptainsLog.Configuration(
                    application: mockApplication,
                    service: CaptainsLog.Configuration.Service(
                        domain: serviceDomain,
                        type: serviceType,
                        port: servicePort),
                    seed: CaptainsLog.Configuration.Seed(
                        commonName: commonName! as String,
                        certificate: publicCertificate))
                let log = CaptainsLog(configuration: logConfiguration)

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

                let serverConfiguration = CaptainsLogServer.Configuration(
                    logViewer: mockLogViewer,
                    serviceDomain: serviceDomain,
                    serviceType: serviceType)
                let server = CaptainsLogServer(configuration: serverConfiguration, identityProvider: identityProvider)

                let logConfiguration = CaptainsLog.Configuration(
                    application: mockApplication,
                    service: CaptainsLog.Configuration.Service(
                        domain: serviceDomain,
                        type: serviceType,
                        port: servicePort),
                    seed: CaptainsLog.Configuration.Seed(
                        commonName: commonName! as String,
                        certificate: publicCertificate))
                let log = CaptainsLog(configuration: logConfiguration)

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
