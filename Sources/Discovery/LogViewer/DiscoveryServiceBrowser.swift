//
//  DiscoveryServiceBrowser.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

final class DiscoveryServiceBrowser: NSObject {

    //    var didResolveServices: (([NetService]) -> Void)?

    private let serviceType: String
    private let serviceDomain: String
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []

    //    private let resolutionQueue = DispatchQueue(label: "org.brightify.CaptainsLog.resolution")

//    private let unresolvedServicesSubject = BehaviorSubject<[NetService]>(value: [])
//    public var unresolvedServices: Observable<[NetService]> {
//        return unresolvedServicesSubject
//    }

    private let unresolvedSevicesObservers = ObserverBag<[NetService]>()

    init(serviceType: String, serviceDomain: String) {
        self.serviceType = serviceType
        self.serviceDomain = serviceDomain

        super.init()

        browser.schedule(in: .main, forMode: .default)
        browser.delegate = self
    }

    func observeUnresolvedServices(observer: @escaping ([NetService]) -> Void) -> Disposable {
        return unresolvedSevicesObservers.register(observer: observer)
    }

    func search() {
        LOG.verbose("Will search for services \(serviceType) in \(serviceDomain)")
        browser.searchForServices(ofType: serviceType, inDomain: serviceDomain)
    }

    func stop() {
        LOG.verbose("Will stop search for services \(serviceType) in \(serviceDomain)")
        browser.stop()
    }

    deinit {
        unresolvedSevicesObservers.dispose()
        browser.delegate = nil
        browser.stop()
    }

    private func notifyObservers() {
        unresolvedSevicesObservers.notifyObservers(value: services)
    }
}

extension DiscoveryServiceBrowser: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        LOG.verbose(#function, browser, service, moreComing)

        services.append(service)

        if !moreComing {
            notifyObservers()
//            unresolvedServicesSubject.onNext(services)

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
        LOG.verbose(#function, browser, service, moreComing)
        // FIXME Implement removing properly
        services.removeAll(where: { $0 == service })

        if !moreComing {
            notifyObservers()
        }
    }

    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        LOG.verbose(#function, browser)
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        LOG.verbose(#function, browser)

        services.removeAll()
        notifyObservers()
    }
}
