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

extension DiscoveryServiceBrowser {
    var unresolvedServices: Observable<[NetService]> {
        return Observable.create { observer in
            let disposable = self.observeUnresolvedServices { services in
                observer.onNext(services)
            }

            return RxSwift.Disposables.create {
                disposable.dispose()
            }
        }
    }
}

extension NetService {
    private class AcceptDelegate: NSObject, NetServiceDelegate {
        private let didAcceptConnection: (TwoWayStream) -> Void

        init(didAcceptConnection: @escaping (TwoWayStream) -> Void) {
            self.didAcceptConnection = didAcceptConnection
        }

        func netService(_ sender: NetService, didAcceptConnectionWith inputStream: InputStream, outputStream: OutputStream) {
            LOG.verbose(#function, sender)
            didAcceptConnection(TwoWayStream(input: inputStream, output: outputStream))
        }

        func netServiceWillPublish(_ sender: NetService) {
            LOG.verbose(#function, sender)
        }

        func netServiceDidPublish(_ sender: NetService) {
            LOG.verbose(#function, sender)
            sender.setTXTRecord(sender.txtRecordData())
        }

        func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
            LOG.verbose(#function, sender, errorDict)
        }
    }

    func publish() -> Observable<TwoWayStream> {
        return Observable.create { observer in
            let delegate = AcceptDelegate(didAcceptConnection: observer.onNext)
            self.delegate = delegate

            self.schedule(in: .main, forMode: .default)
            self.publish(options: .listenForConnections)

            return Disposables.create {
                withExtendedLifetime(delegate) { }
                self.delegate = nil
                self.stop()
            }
        }
    }
}

extension CaptainsLogServer {
    private class ServerDelegate: NSObject, CaptainsLogServerDelegate {
        private let didReceiveItem: (LogItem) -> Void

        init(didReceiveItem: @escaping (LogItem) -> Void) {
            self.didReceiveItem = didReceiveItem
        }

        func server(_ server: CaptainsLogServer, didReceive item: LogItem, connection: LoggerConnection) {
            didReceiveItem(item)
        }
    }

    var itemReceived: Observable<LogItem> {
        return Observable.create { observer in
            let delegate = ServerDelegate(didReceiveItem: observer.onNext)
            self.delegate = delegate

            return Disposables.create {
                withExtendedLifetime(delegate) { }
                self.delegate = nil
                self.stop()
            }
        }
    }
}

class DiscoverySpec: QuickSpec {
    override func spec() {
        describe("the 'Discovery' workflow") {
            beforeSuite {
                PrintLogging(limit: .verbose).activate()
                AsyncDefaults.Timeout = 20
                AsyncDefaults.PollInterval = 0.1
            }
            afterSuite {
                AsyncDefaults.Timeout = 1
                AsyncDefaults.PollInterval = 0.01
            }

            // This let's us disambiguate between multiple running tests
            var service: CaptainsLogServer.Configuration.Service!
            beforeEach {
                let testIdentifier = UUID().uuidString.prefix(8)
                service = CaptainsLogServer.Configuration.Service(
                    name: "tested-service-\(testIdentifier)",
                    domain: Constants.domain,
                    type: "_captainslog-transmitter-tests-\(testIdentifier)._tcp.",
                    port: 11123)
            }
            let mockApplication = DiscoveryHandshake.ApplicationRun(
                id: UUID().uuidString,
                date: Date(),
                applicationVersion: "0.1",
                seedIdentifier: "ec3f282e-de95-4cdf-a692-66608dc92c05",
                application: DiscoveryHandshake.ApplicationRun.Application(
                    name: "An application",
                    identifier: "org.brightify.CaptainsLogTests"),
                device: DiscoveryHandshake.ApplicationRun.Device(
                    id: "device-id",
                    name: "Device Name",
                    operatingSystem: .macOS,
                    systemVersion: "10.14"))

            let mockLogViewer = DiscoveryHandshake.LogReceiver(
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

            it("finds server") {
                /*
                 Test decription:

                 1. Publish NetService on computer
                 2. Run NetServiceBrowser search on device
                 3. Connect to found services
                 4. Receive logger url from search
                 */

                let deviceService: NetService = NetService.loggerService(
                    named: "finds server",
                    identifier: "ec3f282e-de95-4cdf-a692-66608dc92c05",
                    domain: service.domain,
                    type: service.type,
                    port: service.port)

                deviceService.publish() as Void
                let browser = DiscoveryServiceBrowser(serviceType: service.type, serviceDomain: service.domain)
                browser.search()
                expect(browser.unresolvedServices.map { $0.first }).first.toNot(beNil())
                deviceService.stop()
            }

            it("finds server multiple times") {
                /*
                 Test decription:

                 1. Publish NetService on computer
                 2. Run NetServiceBrowser search on device
                 3. Connect to found services
                 4. Receive logger url from search
                 */

                let deviceService: NetService = NetService.loggerService(
                    named: "finds server multiple times",
                    identifier: "ec3f282e-de95-4cdf-a692-66608dc92c05",
                    domain: service.domain,
                    type: service.type,
                    port: service.port)

                deviceService.publish() as Void
                let browser = DiscoveryServiceBrowser(serviceType: service.type, serviceDomain: service.domain)
                browser.search()
                expect(browser.unresolvedServices.map { $0.first }).first.toNot(beNil())
                browser.stop()
                expect(browser.unresolvedServices.map { $0.isEmpty }).first.to(beTrue())
                Thread.sleep(forTimeInterval: 2)
                browser.search()
                expect(browser.unresolvedServices.map { $0.first }).first.toNot(beNil())

                deviceService.stop()
            }

            it("connects to server") {
                let clientConnector = DiscoveryLoggerConnector(applicationRun: mockApplication, certificate: publicCertificate)
                let serverConnector = DiscoveryLogViewerConnector(logViewer: mockLogViewer, identityProvider: identityProvider)

                let deviceService = NetService.loggerService(
                    named: "connects to server",
                    identifier: "ec3f282e-de95-4cdf-a692-66608dc92c05",
                    domain: service.domain,
                    type: service.type,
                    port: service.port)

                let browser = DiscoveryServiceBrowser(serviceType: service.type, serviceDomain: service.domain)

                var loggerConnection: LoggerConnection?
                var logViewerConnection: LogViewerConnection?

                // Device
                _ = async {
                    browser.search()

                    let services = try await(browser.unresolvedServices.take(1).asSingle())
                    let connections = try services.map {
                        try await(clientConnector.connect(service: $0))
                    }
                    logViewerConnection = connections.first
                    logViewerConnection?.close()
                }

                // Log server
                _ = async {
                    let stream = try await(deviceService.publish().take(1).asSingle())
                    loggerConnection = try await(serverConnector.connect(stream: stream, lastLogItemId: { _ in .unassigned }))
                    loggerConnection?.close()
                }

                expect(loggerConnection).toEventuallyNot(beNil())
                expect(logViewerConnection).toEventuallyNot(beNil())

                expect(loggerConnection?.applicationRun).toEventually(equal(mockApplication))
                expect(logViewerConnection?.logViewer).toEventually(equal(mockLogViewer))
            }

            it("sends logged items") {
                var logItem: LogItem?
                var loggerConnection: LoggerConnection?

                let serverConnector = DiscoveryLogViewerConnector(logViewer: mockLogViewer, identityProvider: identityProvider)
                let deviceService = NetService.loggerService(
                    named: "sends logged items",
                    identifier: "ec3f282e-de95-4cdf-a692-66608dc92c05",
                    domain: service.domain,
                    type: service.type,
                    port: service.port)

                let logConfiguration = CaptainsLog.Configuration(
                    applicationRun: mockApplication,
                    discovery: NetServiceReceiverDiscovery(type: service.type, domain: service.domain),
                    seed: CaptainsLog.Configuration.Seed(
                        commonName: commonName! as String,
                        certificate: publicCertificate))
                let log = CaptainsLog(configuration: logConfiguration)

                _ = async {
                    let stream = try await(deviceService.publish().take(1).asSingle())
                    loggerConnection = try await(serverConnector.connect(stream: stream, lastLogItemId: { _ in .unassigned }))

                    logItem = try loggerConnection?.stream.input.readDecodable(LogItem.self)

                    loggerConnection?.close()
                }

                _ = async {
                    log.log(item: mockLogItem1)
                }

                expect(loggerConnection).toEventuallyNot(beNil())
                expect(logItem).toEventuallyNot(beNil())

                expect(loggerConnection?.applicationRun).toEventually(equal(mockApplication))
                expect(logItem).toEventually(equal(mockLogItem1))
            }

            fit("reconnects on connection closed") {
                var logItem1: LogItem?
                var logItem2: LogItem?

                let serverConfiguration = CaptainsLogServer.Configuration(
                    logViewer: mockLogViewer,
                    service: service)
                let server = CaptainsLogServer(configuration: serverConfiguration, identityProvider: identityProvider)

                let logConfiguration = CaptainsLog.Configuration(
                    applicationRun: mockApplication,
                    discovery: NetServiceReceiverDiscovery(type: service.type, domain: service.domain),
                    seed: CaptainsLog.Configuration.Seed(
                        commonName: commonName! as String,
                        certificate: publicCertificate))
                let log = CaptainsLog(configuration: logConfiguration)

                _ = async(on: DispatchQueue(label: "LogViewer")) {
                    server.start()

                    logItem1 = try server.itemReceived.toBlocking().first()
                    logItem2 = try server.itemReceived.toBlocking().first()
                }

                _ = async(on: DispatchQueue(label: "Logger")) {
                    Thread.sleep(forTimeInterval: 1)

                    log.log(item: mockLogItem1)

                    Thread.sleep(forTimeInterval: 0.1)

                    log.simulateDisconnect(timeBetweenReconnect: 2)

                    Thread.sleep(forTimeInterval: 0.1)

                    log.log(item: mockLogItem2)
                }

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
                    service: service)
                let server = CaptainsLogServer(configuration: serverConfiguration, identityProvider: identityProvider)

                let logConfiguration = CaptainsLog.Configuration(
                    applicationRun: mockApplication,
                    discovery: NetServiceReceiverDiscovery(type: service.type, domain: service.domain),
                    seed: CaptainsLog.Configuration.Seed(
                        commonName: commonName! as String,
                        certificate: publicCertificate))
                let log = CaptainsLog(configuration: logConfiguration)

                _ = async(on: DispatchQueue(label: "LogViewer")) {
                    server.start()

                    logItem1 = try server.itemReceived.debug("item1 received").toBlocking().first()
                    logItem2 = try server.itemReceived.debug("item2 received").toBlocking().first()

                }

                _ = async(on: DispatchQueue(label: "Logger")) {
                    log.log(item: mockLogItem1)

                    log.simulateDisconnect(timeBetweenReconnect: 2)

                    log.log(item: mockLogItem2)
                }

                expect(logItem1).toEventuallyNot(beNil())
                expect(logItem2).toEventuallyNot(beNil())

                expect(logItem1).toEventually(equal(mockLogItem1))
                expect(logItem2).toEventually(equal(mockLogItem2))
            }
        }
    }
}



public func await<T>(timeout: DispatchTime = .distantFuture, _ maybe: Maybe<T>) throws -> T? {
    do {
        return try await(timeout: timeout, maybe.asObservable().asSingle())
    } catch RxError.noElements {
        return nil
    } catch {
        throw error
    }
}

public func await<T>(timeout: DispatchTime = .distantFuture, _ single: Single<T>) throws -> T {
    var event: SingleEvent<T>?

    let semaphore = DispatchSemaphore(value: 0)

    let subscription = single
        .subscribeOn(ConcurrentDispatchQueueScheduler(queue: Queue.await))
        .observeOn(ConcurrentDispatchQueueScheduler(queue: Queue.await))
        .subscribe { e in
            dispatchPrecondition(condition: .onQueue(Queue.await))

            event = e

            semaphore.signal()
        }
    defer { subscription.dispose() }

    let waitingResult = semaphore.wait(timeout: timeout)

    switch (waitingResult, event) {
    case (.success, .success(let value)?):
        return value

    case (.success, .error(let error)?):
        throw error

    case (.success, nil):
        fatalError("Something signalled the semaphore without providing a result!")

    case (.timedOut, _):
        throw AwaitTimeoutError()
    }
}
//
//public func await<T>(timeout: DispatchTime = .distantFuture, _ body: @escaping () throws -> T) throws -> T {
//    let single = Single<T>.create { resolve in
//        dispatchPrecondition(condition: .onQueue(Queue.await))
//
//        do {
//            resolve(.success(try body()))
//        } catch {
//            resolve(.error(error))
//        }
//
//        return Disposables.create()
//    }
//
//    return try await(timeout: timeout, single)
//}
//
//@discardableResult
//public func async<T>(on queue: DispatchQueue = Queue.async, _ body: @escaping () throws -> T) -> Single<T> {
//    return Single<T>.create { resolved in
//        dispatchPrecondition(condition: .onQueue(queue))
//
//        do {
//            let value = try body()
//            resolved(.success(value))
//        } catch {
//            resolved(.error(error))
//        }
//
//        return Disposables.create()
//    }.subscribeOn(ConcurrentDispatchQueueScheduler(queue: queue))
//}
