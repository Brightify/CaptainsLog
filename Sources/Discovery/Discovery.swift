//
//  Disovery.swift
//  CaptainsLog
//
//  Created by Robin Krenecky on 19/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

final class DiscoveryClient: NSObject, NetServiceBrowserDelegate {
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
    private let loggerFound: ([URL]) -> Void

    private var discoveredServices: [NetService: NetServiceClientDelegate] = [:]

    init(loggerFound: @escaping ([URL]) -> Void) {
        self.loggerFound = loggerFound

        super.init()

        browser.delegate = self
    }

    func search() {
        browser.searchForServices(ofType: "_captainslog-server._tcp.", inDomain: "local.")
    }

    deinit {
        browser.stop()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print(#function, browser, service, moreComing)

        let delegate = NetServiceClientDelegate { [unowned self] error in
            self.discoveredServices[service] = nil

            let urls: [URL] = service.addresses?.compactMap {
                guard let url = $0.asURL(),
                    var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

                components.port = service.port
                components.scheme = "http"
                return components.url
            } ?? []

            self.loggerFound(urls)
        }
        service.delegate = delegate
        discoveredServices[service] = delegate

        service.resolve(withTimeout: 30)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        print(#function, browser, service, moreComing)

        discoveredServices[service] = nil
    }

    private func resolveLoggerUrl(from data: Data) -> URL? {
        guard var urlComponents = URLComponents(string: "") else {
            fatalError("Never supposed to happen. If crash occurs here, report it immediately!")
        }

        urlComponents.scheme = "http"
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

        return urlComponents
    }
}

final class DiscoveryLoggerService: NSObject, NetServiceDelegate {
    private let service = NetService(
        domain: "local.",
        type: "_captainslog-server._tcp.",
        name: Host.current().localizedName ?? "Unknown",
        port: 1111)

    init(id: String) {
        super.init()
        
        service.delegate = self

        precondition(service.setTXTRecord(NetService.data(fromTXTRecord: ["id": id.data(using: .utf8)!])))
    }

    func publish() {
        service.publish()
    }

    deinit {
        service.stop()
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
