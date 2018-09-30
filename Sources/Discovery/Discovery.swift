//
//  Disovery.swift
//  CaptainsLog
//
//  Created by Robin Krenecky on 19/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

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
                    print("Write error:", streamError)
                    throw streamError
                } else {
                    // FIXME Throw an error, don't crash
//                    fatalError("Couldn't write before close")
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
    func status(equalTo newStatus: Status) -> Promise<Void> {
        return Promise<Void> { resolved, _ in
            func checkAndDelay() {
                guard self.streamStatus != newStatus else {
                    resolved(())
                    return
                }

                Queue.work.asyncAfter(deadline: .now() + 0.1) {
                    checkAndDelay()
                }
            }

            checkAndDelay()
        }
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
            var buffer = bytesPointer.advanced(by: readBytes)
// totalBytes[readBytes...] //  Array<UInt8>(repeating: 0, count: remainingLength)
//            self.read(buffer, maxLength: length - readBytes)
            let readLength = read(buffer, maxLength: length - readBytes)
            guard readLength > 0 else {
                if let streamError = streamError {
                    // FIXME Throw an error, don't crash
                    print("streamError", streamError)
                    throw streamError
                } else {
//                    fatalError("Couldn't read before close")
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

public final class DiscoveryHandshake {
    public struct Logger: Codable, Equatable {
        public let id: String
        public let name: String
    }
    public struct Application: Codable, Equatable {
        public let id: String
        public let name: String
        public let identifier: String
        public let version: String
        public let date: Date
    }

    init() {
    }

    func perform(on connection: DiscoveryConnection, for logger: Logger) -> Promise<Application> {
        return async {
            try await(timeout: .now() + 3, connection.outputStream.status(equalTo: .open))

            print("INFO: Sending logger info:", logger)
            try connection.outputStream.write(encodable: logger)
            print("INFO: Sent logger info.")

            try await(timeout: .now() + 3, connection.inputStream.status(equalTo: .open))
            print("INFO: Receiving app info.")
            let application = try connection.inputStream.readDecodable(Application.self)
            print("INFO: Receiving app info:", application)

            return application
        }
    }


    func perform(on connection: DiscoveryConnection, for application: Application) -> Promise<Logger> {
        return async {
            try await(timeout: .now() + 3, connection.inputStream.status(equalTo: .open))

            print("INFO: Receiving logger info.")
            let logger = try connection.inputStream.readDecodable(Logger.self)
            print("INFO: Receiving logger info:", logger)

            try await(timeout: .now() + 3, connection.outputStream.status(equalTo: .open))
            print("INFO: Sending app info:", application)
            try connection.outputStream.write(encodable: application)
            print("INFO: Sent app info.")

            return logger
        }
    }
}

public enum DiscoveryConnectionSide {
    case server
    case client
}

public enum DiscoveryConnectionId: Codable {
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

public protocol DiscoveryConnection {
    var side: DiscoveryConnectionSide { get }
    var id: String { get }
    var service: NetService { get }
    var inputStream: InputStream { get }
    var outputStream: OutputStream { get }

    func reconnected(inputStream: InputStream, outputStream: OutputStream)
}

public extension DiscoveryConnection {
    func open() {
        print("INFO: Opening connection for service:", side, service)
        inputStream.open()
        print("ERROR:", inputStream.streamError)
        outputStream.open()
        print("ERROR:", outputStream.streamError)
    }

    func close() {
        print("INFO: Closing connection for service:", side, service)
        service.stop()
        inputStream.close()
        outputStream.close()
    }
}

public final class ClientConnection: DiscoveryConnection {
    public let side = DiscoveryConnectionSide.client
    public let id: String
    public let service: NetService
    public private(set) var inputStream: InputStream
    public private(set) var outputStream: OutputStream

    init(id: String, service: NetService) {
        self.id = id
        self.service = service

        var inputStream: InputStream?
        var outputStream: OutputStream?

        precondition(service.getInputStream(&inputStream, outputStream: &outputStream), "Couldn't get streams!")

        self.inputStream = inputStream!
        self.outputStream = outputStream!

        scheduleStreams()
    }

    public func reconnected(inputStream: InputStream, outputStream: OutputStream) {
        print("Old input", self.inputStream, ", new input", inputStream)
        print("Old output", self.outputStream, ", new output", outputStream)

        self.inputStream = inputStream
        self.outputStream = outputStream

        scheduleStreams()
    }

    private func scheduleStreams() {
        inputStream.schedule(in: .current, forMode: .default)
        outputStream.schedule(in: .current, forMode: .default)
    }
}

public final class ServerConnection: DiscoveryConnection {
    public let side = DiscoveryConnectionSide.server
    public let id: String
    public let service: NetService
    public private(set) var inputStream: InputStream
    public private(set) var outputStream: OutputStream

    init(id: String, service: NetService, inputStream: InputStream, outputStream: OutputStream) {
        self.id = id
        self.service = service
        self.inputStream = inputStream
        self.outputStream = outputStream

//        scheduleStreams()
    }

    public func reconnected(inputStream: InputStream, outputStream: OutputStream) {
        print("Old input", self.inputStream, ", new input", inputStream)
        print("Old output", self.outputStream, ", new output", outputStream)

        self.inputStream = inputStream
        self.outputStream = outputStream

//        scheduleStreams()
    }

}

final class DiscoveryServerConnector {
    private struct WeakBox<T: AnyObject> {
        weak var object: T?
    }

    private var pastConnections: [String: WeakBox<ServerConnection>] = [:]

    init() {
    }

    func accept(service: NetService, inputStream: InputStream, outputStream: OutputStream) -> Promise<ServerConnection> {
        return async {
            self.prepareStreams(inputStream: inputStream, outputStream: outputStream)

            let id = try inputStream.readDecodable(DiscoveryConnectionId.self)

            switch id {
            case .assigned(let identifier):
                let existingConnection = self.pastConnections[identifier]

            case .unassigned:
                break
            }

            return ServerConnection(id: "", service: service, inputStream: inputStream, outputStream: outputStream)
        }
    }

    private func prepareStreams(inputStream: InputStream, outputStream: OutputStream) {
        inputStream.schedule(in: .current, forMode: .default)
        outputStream.schedule(in: .current, forMode: .default)
    }
}

final class DiscoveryClientConnector {
    init() {
    }

    func connect(service: NetService) -> Promise<DiscoveryConnection> {
        return async {
            return ClientConnection(id: "", service: service)
        }
    }

    public func withReconnecting<T>(of connection: ClientConnection, reconnectDelay: TimeInterval = 1, do work: () throws -> T) throws -> T {
        do {
            return try work()
        } catch _ as StreamDisconnectedError {
            print("Will reconnect")
            Thread.sleep(forTimeInterval: reconnectDelay)

            return try withReconnecting(of: connection, do: work)
        } catch {
            throw error
        }
    }

    private func prepareStreams(inputStream: InputStream, outputStream: OutputStream) {
        inputStream.schedule(in: .current, forMode: .default)
        outputStream.schedule(in: .current, forMode: .default)


    }

    public func reconnect(client: ClientConnection) {
        // TODO Check if we can close the stream right away or if we need to check if it wasn't closed first
        // if inputStream.streamStatus != .closed {
        client.inputStream.close()
        client.outputStream.close()

        var inputStream: InputStream?
        var outputStream: OutputStream?

        precondition(client.service.getInputStream(&inputStream, outputStream: &outputStream), "Couldn't get streams!")

        client.reconnected(inputStream: inputStream!, outputStream: outputStream!)
    }
}

protocol DiscoveryServiceBrowserDelegate: AnyObject {
    func discoveryServiceBrowser(_ browser: DiscoveryServiceBrowser, didResolveServices: [NetService])
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

    var didResolveServices: (([NetService]) -> Void)?

    private let browser = NetServiceBrowser()
    private var unresolvedServices: [NetService] = []

    private let resolutionQueue = DispatchQueue(label: "org.brightify.CaptainsLog.resolution")

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

        unresolvedServices.append(service)

        if !moreComing {
            let servicesCopy = unresolvedServices
            unresolvedServices = []

            let group = DispatchGroup()

            let delegates = servicesCopy.map { service -> NetServiceClientDelegate in
                group.enter()

                let delegate = NetServiceClientDelegate { error in
                    group.leave()
                }
                service.delegate = delegate
                service.schedule(in: .current, forMode: .default)
                service.resolve(withTimeout: 30)
                return delegate
            }

            group.notify(queue: .main) {
                withExtendedLifetime(delegates) { }
                self.didResolveServices?(servicesCopy)
            }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        print(#function, browser, service, moreComing)
        // FIXME Implement removing properly
        unresolvedServices.removeAll(where: { $0 == service })
    }
}

final class DiscoveryService: NSObject {
    static let domain = "local."
    static let type = "_captainslog-transmitter._tcp."
    static let port = 0 as Int32

    private let service: NetService

    private let pendingConnectionLock = DispatchQueue(label: "service-queue")
    private var pendingConnectionPromise: Promise<DiscoveryConnection>?
    private var pendingConnections: [DiscoveryConnection] = [] {
        didSet {
            guard !pendingConnections.isEmpty else { return }
            pendingConnectionPromise?.resolve(pendingConnections.removeFirst())
        }
    }

    private let connector = DiscoveryServerConnector()

    init(
        domain: String = DiscoveryService.domain,
        type: String = DiscoveryService.type,
        name: String,
        port: Int32 = DiscoveryService.port) {

        service = NetService(
            domain: domain,
            type: type,
            name: name, // Host.current().localizedName ?? "Unknown"
            port: port)

        super.init()

        service.delegate = self

        service.schedule(in: .current, forMode: .default)
        service.publish(options: .listenForConnections)
    }

    deinit {
        print("Service deinited")
        service.delegate = nil
        service.stop()
    }
}

extension DiscoveryService {
    func acceptConnection() -> Promise<DiscoveryConnection> {
        return pendingConnectionLock.sync {
            if !pendingConnections.isEmpty {
                let firstPendingConnection = pendingConnections.removeFirst()
                let promise = Promise<DiscoveryConnection>.pending()
                promise.resolve(firstPendingConnection)
                return promise
            } else {
                let promise = Promise<DiscoveryConnection>.pending()
                promise.ensure { [weak self] in
                    self?.pendingConnectionPromise = nil
                }
                pendingConnectionPromise = promise
                return promise
            }
        }
    }
}

extension DiscoveryService: NetServiceDelegate {
    func netService(_ sender: NetService, didAcceptConnectionWith inputStream: InputStream, outputStream: OutputStream) {
        print(#function)

        async {
            let connection = try await(self.connector.accept(service: sender, inputStream: inputStream, outputStream: outputStream))

            self.pendingConnectionLock.sync {
                self.pendingConnections.append(connection)
            }
        }
    }

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
}
