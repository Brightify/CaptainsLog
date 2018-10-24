//
//  CaptainsLog.swift
//  CaptainsLog
//
//  Created by Robin Krenecky on 19/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation
#if canImport(RxSwift)
import RxSwift
#endif

public final class CaptainsLog {
    public struct Configuration {
        public var application: DiscoveryHandshake.Application
        public var serviceDomain: String
        public var serviceType: String
        public var servicePort: Int

        public init(
            application: DiscoveryHandshake.Application,
            serviceDomain: String,
            serviceType: String,
            servicePort: Int) {

            self.application = application
            self.serviceDomain = serviceDomain
            self.serviceType = serviceType
            self.servicePort = servicePort
        }
    }

    private static var appInfo: DiscoveryHandshake.Application {
        return DiscoveryHandshake.Application(
            id: UUID().uuidString,
            name: Bundle.main.infoDictionary![kCFBundleNameKey as String] as! String,
            identifier: Bundle.main.infoDictionary![kCFBundleIdentifierKey as String] as! String,
            version: Bundle.main.infoDictionary![kCFBundleVersionKey as String] as! String,
            date: Date())
    }
    public static let instance = CaptainsLog(configuration:
        CaptainsLog.Configuration(
            application: appInfo,
            serviceDomain: Constants.domain,
            serviceType: Constants.type,
            servicePort: Constants.port))

    private let senderLock = DispatchQueue(label: "org.brightify.CaptainsLog.senderlock")

    private var logItems: [LogItem] = []
    private var senders: [LogSender] = []

    private let configuration: Configuration
    private let loggerService: NetService
    private let connector: DiscoveryLoggerConnector
    private let disposeBag = DisposeBag()

    init(configuration: Configuration) {
        self.configuration = configuration
        connector = DiscoveryLoggerConnector(application: configuration.application)

        loggerService = NetService.loggerService(
            named: "device-name",
            identifier: "mock-...",
            domain: configuration.serviceDomain,
            type: configuration.serviceType,
            port: configuration.servicePort)

        loggerService.publish()
            .flatMap(connector.connect)
            .subscribe(onNext: { [unowned self] connection in
                let initialQueue: [LogItem]
                switch connection.lastReceivedItemId {
                case .assigned(let lastItemId):
                    if let lastReceivedIndex = self.logItems.lastIndex(where: { $0.id == lastItemId }) {
                        let fromIndex = lastReceivedIndex + 1
                        initialQueue = Array(self.logItems[fromIndex...])
                    } else {
                        initialQueue = self.logItems
                    }
                case .unassigned:
                    initialQueue = self.logItems
                }

                let sender = LogSender(connection: connection, queue: initialQueue)
                self.senders.append(sender)
            })
            .disposed(by: disposeBag)
    }

    func log(item: LogItem) {
        print("Sending item:", item)
        senderLock.async {
            self.logItems.append(item)

            for sender in self.senders {
                sender.push(item: item)
            }
        }
    }
}

// XXX: This is for testing purposes only. Ideas how to compile it in only when testing?
extension CaptainsLog {
    func disconnectAll() {
        senders = []
    }

    func simulateDisconnect(timeBetweenReconnect: TimeInterval) {
        senders = []
        loggerService.stop()

        Thread.sleep(forTimeInterval: timeBetweenReconnect)

        loggerService.publish(options: .listenForConnections)
    }
}
