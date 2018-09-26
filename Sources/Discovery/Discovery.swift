//
//  Disovery.swift
//  CaptainsLog
//
//  Created by Robin Krenecky on 19/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

struct Test: Codable {
    var a = 10
}

final class DiscoveryServiceConnector {
    struct Connection {
        let inputStream: InputStream
        let outputStream: OutputStream
    }

    let connection: Connection
    var sent: Int = -2

    let queue = DispatchQueue(label: "connector-queue")

    init(service: NetService) {

//        service

//        CFStreamCreatePairWithSocketToNetService(nil, cfNetService, &readStream, &writeStream)
        var inputStream: InputStream?
        var outputStream: OutputStream?

        precondition(service.getInputStream(&inputStream, outputStream: &outputStream), "Couldn't get streams!")

        connection = Connection(inputStream: inputStream!, outputStream: outputStream!)
    }

    func connect() {
        queue.async {
        self.connection.inputStream.schedule(in: RunLoop.main, forMode: .default)
        self.connection.outputStream.schedule(in: RunLoop.main, forMode: .default)

//        DispatchQueue(label: "background send").async {
        self.connection.inputStream.open()
        self.connection.outputStream.open()

        let encoder = JSONEncoder()
        let data = try! encoder.encode(Test())

        self.sent = data.withUnsafeBytes {
            self.connection.outputStream.write($0, maxLength: data.count)
        }

        self.connection.inputStream.close()
        self.connection.outputStream.close()
        }
//        }
    }

//    func connect() -> (i: InputStream?, o: OutputStream?) {
//let a = CFAllocatorGetDefault()
//        let socket = SocketPort(remoteWithTCPPort: port, host: host)
//CFStreamCreatePairWithSocketToNetService(<#T##alloc: CFAllocator?##CFAllocator?#>, <#T##service: CFNetService##CFNetService#>, <#T##readStream: UnsafeMutablePointer<Unmanaged<CFReadStream>?>?##UnsafeMutablePointer<Unmanaged<CFReadStream>?>?#>, <#T##writeStream: UnsafeMutablePointer<Unmanaged<CFWriteStream>?>?##UnsafeMutablePointer<Unmanaged<CFWriteStream>?>?#>)
//        var inputStream: InputStream?
//        var outputStream: OutputStream?
//
//
//
//
//        Stream.getStreamsToHost(withName: host, port: port, inputStream: &inputStream, outputStream: &outputStream)
//        fatalError()
//        return (i: inputStream, o: outputStream)
//        inputStream?.close()
//        outputStream?.close()

//        CFStreamCreatePairWithSocket(a, socket?.socket, UnsafeMutablePointer<Unmanaged<CFReadStream>?>!, UnsafeMutablePointer<Unmanaged<CFWriteStream>?>!)


//        socket?.socket.
//    }

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

    private let browser = NetServiceBrowser()
//    private let loggerFound: ([URL]) -> Void
    private let resolvedService: (NetService) -> Void

    private var discoveredServices: [NetService: NetServiceClientDelegate] = [:]

    let queue = DispatchQueue(label: "browser-queue")

//    init(loggerFound: @escaping ([URL]) -> Void) {

    init(resolvedService: @escaping (NetService) -> Void) {
//        self.loggerFound = loggerFound
        self.resolvedService = resolvedService

        super.init()

        browser.delegate = self
    }

    func search() {
        queue.sync {
            browser.searchForServices(ofType: "_captainslog-transmitter._tcp.", inDomain: "local.")
        }
    }

    deinit {
        browser.stop()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print(#function, browser, service, moreComing)

        let delegate = NetServiceClientDelegate { [unowned self] error in
            self.discoveredServices[service] = nil

//            let urls: [URL] = service.addresses?.compactMap { addressData in
//                self.resolveLoggerUrl(from: addressData, port: service.port)
//            } ?? []

            self.resolvedService(service)
//            self.loggerFound(urls)
        }
        service.delegate = delegate
        discoveredServices[service] = delegate

        service.resolve(withTimeout: 30)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        print(#function, browser, service, moreComing)

        discoveredServices[service] = nil
    }

    private func resolveLoggerUrl(from data: Data, port: Int) -> URL? {
        guard var urlComponents = URLComponents(string: "") else {
            fatalError("Never supposed to happen. If crash occurs here, report it immediately!")
        }

        urlComponents.port = 1111

        let inetAddress = data.withUnsafeBytes { (pointer: UnsafePointer<sockaddr_in>) -> sockaddr_in in
            pointer.pointee
        }
        if inetAddress.sin_family == __uint8_t(AF_INET) {
            if let ip = String(cString: inet_ntoa(inetAddress.sin_addr), encoding: .ascii) {
                // IPv4
                urlComponents.host = ip
            }
        } else if inetAddress.sin_family == __uint8_t(AF_INET6) {
            let inetAddress6: sockaddr_in6 = data.withUnsafeBytes { (pointer: UnsafePointer<sockaddr_in6>) in
                pointer.pointee
            }
            let ipStringBuffer = UnsafeMutablePointer<Int8>.allocate(capacity: Int(INET6_ADDRSTRLEN))
            defer { ipStringBuffer.deallocate() }
            var addr = inetAddress6.sin6_addr

            if let ipString = inet_ntop(Int32(inetAddress6.sin6_family), &addr, ipStringBuffer, __uint32_t(INET6_ADDRSTRLEN)) {
                if let ip = String(cString: ipString, encoding: .ascii) {
                    // IPv6
                    print(ip)
                    urlComponents.host = ip
                }
            }
        } else {
            return nil
        }

        return urlComponents.url
    }
}

final class DiscoveryService: NSObject, NetServiceDelegate {
    static let domain = "local."
    static let type = "_captainslog-transmitter._tcp."

    private let service: NetService

    let queue = DispatchQueue(label: "service-queue")

    init(name: String, id: String) {
        service = NetService(
            domain: DiscoveryService.domain,
            type: DiscoveryService.type,
            name: name, // Host.current().localizedName ?? "Unknown"
            port: 0)

        super.init()

        service.delegate = self

        precondition(service.setTXTRecord(NetService.data(fromTXTRecord: ["id": id.data(using: .utf8)!])))
    }

    func publish() {
        queue.sync {
            service.publish(options: .listenForConnections)
            service.schedule(in: RunLoop.main, forMode: RunLoop.Mode.default)
        }
    }

    deinit {
        queue.sync {
            service.stop()
        }
    }

    func netService(_ sender: NetService, didAcceptConnectionWith inputStream: InputStream, outputStream: OutputStream) {
        print(#function)
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        print(#function)
    }

    func netService(_ sender: NetService, didUpdateTXTRecord data: Data) {
        print(#function)
    }

    func netServiceWillPublish(_ sender: NetService) {
        print(#function)
    }

    func netServiceDidPublish(_ sender: NetService) {
        print(#function)
    }

    func netServiceDidStop(_ sender: NetService) {
        print(#function)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print(#function)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        print(#function)
    }

    func netServiceWillResolve(_ sender: NetService) {
        print(#function)
    }
}

func x() {
//    let service = NetService(domain: <#T##String#>, type: <#T##String#>, name: <#T##String#>, port: 1111)

//    let service = NetService(domain: "local.", type: "_hap._tcp.", name: "Zithoek", port: 0)
//    service.publish(options: [.listenForConnections])
//    service.schedule(in: .main, forMode: .defaultRunLoopMode)
//
//    service.delegate
//    service.delegate = ...
//        withExtendedLifetime((service, delegate)) {
//            RunLoop.main.run()
//    }
}


func y() {
//    let browser = NetServiceBrowser()
//    browser.searchForServices(ofType: "_airplay._tcp.", inDomain: "local.")

//    browser.delegate = ...
//        withExtendedLifetime((browser, delegate)) {
//            RunLoop.main.run()
//    }
}
