//
//  DiscoveryServiceBrowser.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation
import RxSwift

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
