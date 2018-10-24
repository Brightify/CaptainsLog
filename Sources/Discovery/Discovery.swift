//
//  Disovery.swift
//  CaptainsLog
//
//  Created by Robin Krenecky on 19/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation
import RxSwift

private func toByteArray<T>(_ value: T) -> [UInt8] {
    var value = value
    return withUnsafeBytes(of: &value) { Array($0) }
}

private func fromByteArray<T>(_ value: [UInt8], _: T.Type = T.self) -> T {
    return value.withUnsafeBytes {
        $0.baseAddress!.load(as: T.self)
    }
}

private let encoder = JSONEncoder()

public extension OutputStream {
    func write<T>(raw value: T) throws {
        let bytes = toByteArray(value)
        try write(bytes: bytes)
    }

    func write(bytes: [UInt8]) throws {
        let totalBytes = bytes.count
        let bytesPointer = UnsafePointer(bytes)
        var totalWrittenBytes = 0

        repeat {
            let buffer = bytesPointer.advanced(by: totalWrittenBytes)
            let writtenBytes = write(buffer, maxLength: totalBytes - totalWrittenBytes)

            guard writtenBytes > 0 else {
                if let streamError = streamError {
                    throw streamError
                } else {
                    throw StreamDisconnectedError()
                }
            }

            totalWrittenBytes += writtenBytes

        } while totalWrittenBytes < totalBytes
    }

    func write(data: Data) throws {
        let bytes = Array(data)
        try write(raw: bytes.count)
        try write(bytes: bytes)
    }

    func write<T: Encodable>(encodable value: T) throws {
        let data = try encoder.encode(value)
        try write(data: data)
    }
}

private let decoder = JSONDecoder()

public extension Stream {
    func observeStatus() -> Observable<Status> {
        return Observable<Int>.timer(0.1, scheduler: MainScheduler.instance)
            .map { _ in self.streamStatus }
            .startWith(streamStatus)
            .distinctUntilChanged()
    }

    func status(isOneOf acceptedStates: Status...) -> Maybe<Status> {
        let acceptedStateSet = Set(acceptedStates)
        return observeStatus()
            .filter(acceptedStateSet.contains)
            .take(1)
            .asMaybe()
    }
}

extension Stream.Status: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notOpen:
            return "not open"
        case .opening:
            return "opening"
        case .open:
            return "open"
        case .reading:
            return "reading"
        case .writing:
            return "writing"
        case .atEnd:
            return "at end"
        case .closed:
            return "closed"
        case .error:
            return "error"
        }
    }
}

struct StreamDisconnectedError: Error { }

public extension InputStream {
    func readBytes(length: Int) throws -> [UInt8] {
        var totalBytes = Array<UInt8>(repeating: 0, count: length)
        let bytesPointer = UnsafeMutablePointer(&totalBytes)
        var readBytes = 0

        repeat {
            let buffer = bytesPointer.advanced(by: readBytes)
            let readLength = read(buffer, maxLength: length - readBytes)
            guard readLength > 0 else {
                if let streamError = streamError {
                    throw streamError

                } else {
                    throw StreamDisconnectedError()
                }
            }

            readBytes += readLength
        } while readBytes < length

        return totalBytes
    }

    func readRaw<T>(_ type: T.Type = T.self) throws -> T {
        let bytes = try readBytes(length: MemoryLayout<T>.size)
        return fromByteArray(bytes)
    }

    func readData() throws -> Data {
        let length = try readRaw(Int.self)
        let dataBytes = try readBytes(length: length)

        return Data(bytes: dataBytes)
    }

    func readDecodable<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        let data = try readData()
        return try decoder.decode(T.self, from: data)
    }
}

// TODO Handshake should encorporate encryption and signature verification
public final class DiscoveryHandshake {
    public struct LogViewer: Codable, Equatable {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }
    public struct Application: Codable, Equatable {
        public let id: String
        public let name: String
        public let identifier: String
        public let version: String
        public let date: Date

        public init(id: String, name: String, identifier: String, version: String, date: Date) {
            self.id = id
            self.name = name
            self.identifier = identifier
            self.version = version
            self.date = date
        }
    }

    private let stream: TwoWayStream

    init(stream: TwoWayStream) {
        self.stream = stream
    }

    func perform(for viewer: LogViewer) throws -> Application {
            print("INFO: Sending logger info:", viewer)
            try stream.output.write(encodable: viewer)
            print("INFO: Sent logger info.")

            print("INFO: Receiving app info.")
            let application = try stream.input.readDecodable(Application.self)
            print("INFO: Receiving app info:", application)

            return application
    }


    func perform(for application: Application) throws -> LogViewer {
            print("INFO: Receiving logger info.")
            let logViewer = try stream.input.readDecodable(LogViewer.self)
            print("INFO: Receiving logger info:", logViewer)

            print("INFO: Sending app info:", application)
            try stream.output.write(encodable: application)
            print("INFO: Sent app info.")

            return logViewer
    }
}

public enum DiscoveryConnectionSide {
    case server
    case client
}

public enum LastLogItemId: Codable {
    case unassigned
    case assigned(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(IdType.self, forKey: .type)
        switch type {
        case .assigned:
            let value = try container.decode(String.self, forKey: .value)
            self = .assigned(value)
        case .unassigned:
            self = .unassigned
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .assigned(let id):
            try container.encode(IdType.assigned, forKey: .type)
            try container.encode(id, forKey: .value)
        case .unassigned:
            try container.encode(IdType.unassigned, forKey: .type)
        }
    }
    private enum IdType: String, Codable {
        case unassigned
        case assigned
    }
    private enum CodingKeys: CodingKey {
        case type
        case value
    }
}

public final class LoggerConnection {
    public let service: NetService
    public let application: DiscoveryHandshake.Application

    public private(set) var stream: TwoWayStream

    init(service: NetService, stream: TwoWayStream, application: DiscoveryHandshake.Application) {
        self.service = service
        self.stream = stream
        self.application = application
    }

    func close() {
        print("INFO: Closing connection for logger service:", service)
        service.stop()
        stream.input.close()
        stream.output.close()
    }
}

public final class LogViewerConnection {
    public let stream: TwoWayStream
    public let logViewer: DiscoveryHandshake.LogViewer
    public let lastReceivedItemId: LastLogItemId

    init(stream: TwoWayStream, logViewer: DiscoveryHandshake.LogViewer, lastReceivedItemId: LastLogItemId) {
        self.stream = stream
        self.logViewer = logViewer
        self.lastReceivedItemId = lastReceivedItemId
    }

    func close() {
        stream.input.close()
        stream.output.close()
    }
}

final class DiscoveryServerConnector {
    private let application: DiscoveryHandshake.Application

    init(application: DiscoveryHandshake.Application) {
        self.application = application
    }

    func connect(stream: TwoWayStream) -> Single<LogViewerConnection> {
        return async {
            try await(stream.open().debug("server connect"))

            let logViewer = try DiscoveryHandshake(stream: stream).perform(for: self.application)

            let lastItemId = try stream.input.readDecodable(LastLogItemId.self)

            return LogViewerConnection(stream: stream, logViewer: logViewer, lastReceivedItemId: lastItemId)
        }
    }
}

final class DiscoveryClientConnector {
    private let logViewer: DiscoveryHandshake.LogViewer

    init(logViewer: DiscoveryHandshake.LogViewer) {
        self.logViewer = logViewer
    }

    func connect(service: NetService, lastLogItemId: @escaping (DiscoveryHandshake.Application) -> LastLogItemId) -> Single<LoggerConnection> {
        return async {
            let resolvedService = try await(service.resolved(withTimeout: 30))

            var inputStream: InputStream?
            var outputStream: OutputStream?

            precondition(resolvedService.getInputStream(&inputStream, outputStream: &outputStream), "Couldn't get streams!")

            let stream = TwoWayStream(input: inputStream!, output: outputStream!)

            try await(stream.open())

            let application = try DiscoveryHandshake(stream: stream).perform(for: self.logViewer)

            try stream.output.write(encodable: lastLogItemId(application))

            return LoggerConnection(service: resolvedService, stream: stream, application: application)
        }
    }

//    public func withReconnecting<T>(of connection: LoggerConnection, reconnectDelay: TimeInterval = 1, do work: () throws -> T) throws -> T {
//        do {
//            return try work()
//        } catch _ as StreamDisconnectedError {
//            print("Will reconnect")
//            Thread.sleep(forTimeInterval: reconnectDelay)
//
//            connect(service: connection.service)
//
//            return try withReconnecting(of: connection, do: work)
//        } catch {
//            throw error
//        }
//    }

//    private func prepareStreams(inputStream: InputStream, outputStream: OutputStream) {
//        inputStream.schedule(in: .current, forMode: .default)
//        outputStream.schedule(in: .current, forMode: .default)
//
//
//    }

//    public func reconnect(client: LoggerConnection) {
//        // TODO Check if we can close the stream right away or if we need to check if it wasn't closed first
//        // if inputStream.streamStatus != .closed {
//        client.stream.input.close()
//        client.stream.output.close()
//
//        var inputStream: InputStream?
//        var outputStream: OutputStream?
//
//        precondition(client.service.getInputStream(&inputStream, outputStream: &outputStream), "Couldn't get streams!")
//
//        let stream = TwoWayStream(input: inputStream!, output: outputStream!)
//
//        client.
//
//        fatalError("TODO")
////        client.reconnected(inputStream: inputStream!, outputStream: outputStream!)
//    }

//    private func connect(service: NetService) -> TwoWayStream {
//        var inputStream: InputStream?
//        var outputStream: OutputStream?
//
//        precondition(service.getInputStream(&inputStream, outputStream: &outputStream), "Couldn't get streams!")
//
//        return TwoWayStream(input: inputStream!, output: outputStream!)
//    }
}

protocol DiscoveryServiceBrowserDelegate: AnyObject {
    func discoveryServiceBrowser(_ browser: DiscoveryServiceBrowser, didResolveServices: [NetService])
}

extension NetService {
    private final class ResolutionDelegate: NSObject, NetServiceDelegate {
        struct ResolutionError: Error {
            let info: [String: NSNumber]
        }

        let serviceResolved: (ResolutionError?) -> Void

        init(serviceResolved: @escaping (ResolutionError?) -> Void) {
            self.serviceResolved = serviceResolved
        }

        func netServiceDidResolveAddress(_ sender: NetService) {
            print(#function, sender)

            serviceResolved(nil)
        }

        func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
            print(#function, sender, errorDict)

            serviceResolved(ResolutionError(info: errorDict))
        }
    }

    func resolved(withTimeout timeout: TimeInterval) -> Single<NetService> {
        guard addresses == nil else { return .just(self) }

        return Single.create { fullfill in
            let delegate = ResolutionDelegate(serviceResolved: { error in
                if let error = error {
                    fullfill(.error(error))
                } else {
                    fullfill(.success(self))
                }
            })
            self.delegate = delegate

            self.resolve(withTimeout: timeout)

            return Disposables.create {
                withExtendedLifetime(delegate) { }
                self.delegate = nil
            }
        }
    }

}

final class DiscoveryServiceBrowser: NSObject, NetServiceBrowserDelegate {
    final class NetServiceClientDelegate: NSObject, NetServiceDelegate {
        struct ResolutionError: Error {
            let info: [String: NSNumber]
        }

        let serviceResolved: (ResolutionError?) -> Void

        init(serviceResolved: @escaping (ResolutionError?) -> Void) {
            self.serviceResolved = serviceResolved
        }

        func netServiceDidResolveAddress(_ sender: NetService) {
            print(#function, sender)

            serviceResolved(nil)
        }

        func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
            print(#function, sender, errorDict)

            serviceResolved(ResolutionError(info: errorDict))
        }
    }

//    var didResolveServices: (([NetService]) -> Void)?

    private let browser = NetServiceBrowser()
    private var services: [NetService] = []

//    private let resolutionQueue = DispatchQueue(label: "org.brightify.CaptainsLog.resolution")

    private let unresolvedServicesSubject = BehaviorSubject<[NetService]>(value: [])
    public var unresolvedServices: Observable<[NetService]> {
        return unresolvedServicesSubject
    }

    override init() {
        super.init()

        browser.delegate = self
    }

    func search() {
        browser.schedule(in: .current, forMode: .default)
        browser.searchForServices(ofType: "_captainslog-transmitter._tcp.", inDomain: "local.")
    }

    deinit {
        browser.delegate = nil
        browser.stop()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print(#function, browser, service, moreComing)

        services.append(service)

        if !moreComing {
            unresolvedServicesSubject.onNext(services)

//            let servicesCopy = unresolvedServices
//
//            let group = DispatchGroup()
//
//            let delegates = servicesCopy.map { service -> NetServiceClientDelegate in
//                group.enter()
//
//                let delegate = NetServiceClientDelegate { error in
//                    group.leave()
//                }
//                service.delegate = delegate
//                service.schedule(in: .current, forMode: .default)
//                service.resolve(withTimeout: 30)
//                return delegate
//            }
//
//            group.notify(queue: .main) {
//                withExtendedLifetime(delegates) { }
//                self.didResolveServices?(servicesCopy)
//            }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        print(#function, browser, service, moreComing)
        // FIXME Implement removing properly
        services.removeAll(where: { $0 == service })

        if moreComing {
            unresolvedServicesSubject.onNext(services)
        }
    }

    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        print(#function, browser)
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        print(#function, browser)
    }
}

struct Constants {
    static let domain = "local."
    static let type = "_captainslog-transmitter._tcp."
    static let port = 0 as Int32
}

//final class DiscoveryService: NSObject {
//    static let domain = "local."
//    static let type = "_captainslog-transmitter._tcp."
//    static let port = 0 as Int32
//
//    private let service: NetService
//
//    private let pendingConnectionLock = DispatchQueue(label: "service-queue")
//    private var pendingConnectionPromise: Promise<DiscoveryConnection>?
//    private var pendingConnections: [DiscoveryConnection] = [] {
//        didSet {
//            guard !pendingConnections.isEmpty else { return }
//            pendingConnectionPromise?.resolve(pendingConnections.removeFirst())
//        }
//    }
//
//    private let connector = DiscoveryServerConnector()
//
//    init(
//        domain: String = DiscoveryService.domain,
//        type: String = DiscoveryService.type,
//        name: String,
//        port: Int32 = DiscoveryService.port) {
//
//        service = NetService(
//            domain: domain,
//            type: type,
//            name: name, // Host.current().localizedName ?? "Unknown"
//            port: port)
//
//        super.init()
//
//        service.delegate = self
//
//        service.schedule(in: .current, forMode: .default)
//        service.publish(options: .listenForConnections)
//    }
//
//    deinit {
//        print("Service deinited")
//        service.delegate = nil
//        service.stop()
//    }
//}

public struct TwoWayStream {
    public let input: InputStream
    public let output: OutputStream

    enum OpenError: Error {
        case cantOpenInput(Error?)
        case cantOpenOutput(Error?)
    }

    public func open(schedulingIn runLoop: RunLoop = .current, forMode runLoopMode: RunLoop.Mode = .default) -> Single<Void> {
        return async {
            self.input.setProperty(StreamSocketSecurityLevel.tlSv1, forKey: Stream.PropertyKey.socketSecurityLevelKey)

            CFReadStreamSetProperty(
                self.input,
                CFStreamPropertyKey(kCFStreamPropertySSLSettings),
                [kCFStreamSSLIsServer: true] as CFDictionary)
            self.input.schedule(in: runLoop, forMode: runLoopMode)
            self.input.open()
            // Wait for input stream to open
            let inputStatus = try await(self.input.status(isOneOf: .open, .error)) ?? .error
            if inputStatus == .error {
                throw OpenError.cantOpenInput(self.input.streamError)
            }

            self.output.setProperty(StreamSocketSecurityLevel.tlSv1, forKey: Stream.PropertyKey.socketSecurityLevelKey)
            self.output.schedule(in: runLoop, forMode: runLoopMode)
            self.output.open()
            // Wait for output stream to open
            let outputStatus = try await(self.output.status(isOneOf: .open, .error)) ?? .error
            if outputStatus == .error {
                throw OpenError.cantOpenOutput(self.output.streamError)
            }
        }
    }
}

extension NetService {
    static func loggerService(
        named name: String,
        domain: String = Constants.domain,
        type: String = Constants.type,
        port: Int32 = Constants.port) -> NetService {

        return NetService(domain: domain, type: type, name: name, port: port)
    }
}

extension NetService {
    private class AcceptDelegate: NSObject, NetServiceDelegate {
        private let didAcceptConnection: (TwoWayStream) -> Void

        init(didAcceptConnection: @escaping (TwoWayStream) -> Void) {
            self.didAcceptConnection = didAcceptConnection
        }

        func netService(_ sender: NetService, didAcceptConnectionWith inputStream: InputStream, outputStream: OutputStream) {
            didAcceptConnection(TwoWayStream(input: inputStream, output: outputStream))
        }
    }

    func publish() -> Observable<TwoWayStream> {
        return Observable.create { observer in
            let delegate = AcceptDelegate(didAcceptConnection: observer.onNext)
            self.delegate = delegate

            self.schedule(in: .current, forMode: .default)
            self.publish(options: .listenForConnections)

            return Disposables.create {
                withExtendedLifetime(delegate) { }
                self.delegate = nil
                self.stop()
            }
        }
    }
}

//extension DiscoveryService {
//
//
//    func acceptConnection() -> Observable<DiscoveryConnection> {
//        return Obser
//        return pendingConnectionLock.sync {
//            if !pendingConnections.isEmpty {
//                let firstPendingConnection = pendingConnections.removeFirst()
//                let promise = Promise<DiscoveryConnection>.pending()
//                promise.resolve(firstPendingConnection)
//                return promise
//            } else {
//                let promise = Promise<DiscoveryConnection>.pending()
//                promise.ensure { [weak self] in
//                    self?.pendingConnectionPromise = nil
//                }
//                pendingConnectionPromise = promise
//                return promise
//            }
//        }
//    }
//}

//extension DiscoveryService: NetServiceDelegate {
//    func netService(_ sender: NetService, didAcceptConnectionWith inputStream: InputStream, outputStream: OutputStream) {
//        print(#function)
//
//        async {
//            let connection = try await(self.connector.accept(service: sender, inputStream: inputStream, outputStream: outputStream))
//
//            self.pendingConnectionLock.sync {
//                self.pendingConnections.append(connection)
//            }
//        }
//    }

//    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
//        print(#function)
//
//        forEachChildDelegate {
//            $0.netService?(sender, didNotPublish: errorDict)
//        }
//    }
//
//    func netService(_ sender: NetService, didUpdateTXTRecord data: Data) {
//        print(#function)
//
//        forEachChildDelegate {
//            $0.netService?(sender, didUpdateTXTRecord: data)
//        }
//    }
//
//    func netServiceWillPublish(_ sender: NetService) {
//        print(#function)
//
//        forEachChildDelegate {
//            $0.netServiceWillPublish?(sender)
//        }
//    }
//
//    func netServiceDidPublish(_ sender: NetService) {
//        print(#function)
//
//        forEachChildDelegate {
//            $0.netServiceDidPublish?(sender)
//        }
//    }
//
//    func netServiceDidStop(_ sender: NetService) {
//        print(#function)
//
//        forEachChildDelegate {
//            $0.netServiceDidStop?(sender)
//        }
//    }
//
//    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
//        print(#function)
//
//        forEachChildDelegate {
//            $0.netService?(sender, didNotResolve: errorDict)
//        }
//    }
//
//    func netServiceDidResolveAddress(_ sender: NetService) {
//        print(#function)
//
//        forEachChildDelegate {
//            $0.netServiceDidResolveAddress?(sender)
//        }
//    }
//
//    func netServiceWillResolve(_ sender: NetService) {
//        print(#function)
//
//        forEachChildDelegate {
//            $0.netServiceWillResolve?(sender)
//        }
//    }
//}
