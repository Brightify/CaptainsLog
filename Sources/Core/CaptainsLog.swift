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
        public var service: Service
        public var seed: Seed

        public init(
            application: DiscoveryHandshake.Application,
            service: Service,
            seed: Seed) {

            self.application = application
            self.service = service
            self.seed = seed
        }

        public struct Service {
            public var domain: String
            public var type: String
            public var port: Int

            public init(domain: String, type: String, port: Int) {
                self.domain = domain
                self.type = type
                self.port = port
            }
        }

        public struct Seed {
            public var commonName: String
            public var certificate: SecCertificate

            public init(commonName: String, certificate: SecCertificate) {
                self.commonName = commonName
                self.certificate = certificate
            }
        }
    }

    private static var initializedInstance: CaptainsLog?
    public static var instance: CaptainsLog {
        if let initializedInstance = initializedInstance {
            return initializedInstance
        } else {
            let instance = CaptainsLog(configuration: defaultConfiguration())
            initializedInstance = instance
            return instance
        }
    }

    private let senderLock = DispatchQueue(label: "org.brightify.CaptainsLog.senderlock")

    private var logItems: [LogItem] = []
    private var senders: [LogSender] = []

    private let configuration: Configuration
    private let loggerService: NetService
    private let connector: DiscoveryLoggerConnector
    private let disposeBag = DisposeBag()

    init(configuration: Configuration) {
        self.configuration = configuration

        connector = DiscoveryLoggerConnector(
            application: configuration.application,
            certificate: configuration.seed.certificate)

        loggerService = NetService.loggerService(
            named: "device-name",
            identifier: configuration.seed.commonName,
            domain: configuration.service.domain,
            type: configuration.service.type,
            port: configuration.service.port)

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
        LOG.verbose("Sending item:", item)
        senderLock.async {
            self.logItems.append(item)

            for sender in self.senders {
                sender.push(item: item)
            }
        }
    }

    private static func defaultConfiguration() -> CaptainsLog.Configuration {
        guard let seedFileURL = Bundle.main.url(forResource: "CaptainsLogSeed", withExtension: "cer") else {
            fatalError("Captain's Log cannot be initialized without a seed file!")
        }
        guard let certificateData = try? Data(contentsOf: seedFileURL),
            let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) else {
                fatalError("Couldn't load seed file from `\(seedFileURL)`")
        }

        var optionalCommonName: CFString?
        let status = SecCertificateCopyCommonName(certificate, &optionalCommonName)

        guard status == errSecSuccess, let commonName = optionalCommonName as String? else {
            fatalError("Couldn't extract common name from certificate \(certificate).")
        }

        let appInfo = DiscoveryHandshake.Application(
            id: UUID().uuidString,
            name: (Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String) ?? "<Unknown>",
            identifier: (Bundle.main.infoDictionary?[kCFBundleIdentifierKey as String] as? String) ?? "com.unknown",
            version: (Bundle.main.infoDictionary?[kCFBundleVersionKey as String] as? String) ?? "0.0",
            date: Date())

        return CaptainsLog.Configuration(
            application: appInfo,
            service: CaptainsLog.Configuration.Service(
                domain: Constants.domain,
                type: Constants.type,
                port: Constants.port),
            seed: CaptainsLog.Configuration.Seed(
                commonName: commonName,
                certificate: certificate))
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
