//
//  CaptainsLog.swift
//  CaptainsLog
//
//  Created by Robin Krenecky on 19/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

private func generatedDeviceId() -> String {
    let key = "CaptainsLog.DeviceId"
    if let existingIdentifier = UserDefaults.standard.string(forKey: key) {
        return existingIdentifier
    } else {
        let newIdentifier = UUID().uuidString
        UserDefaults.standard.setValue(newIdentifier, forKey: key)
        return newIdentifier
    }
}

#if os(iOS)
private func deviceInfo() -> DiscoveryHandshake.ApplicationRun.Device {
    return DiscoveryHandshake.ApplicationRun.Device(
        id: UIDevice.current.identifierForVendor?.uuidString ?? generatedDeviceId(),
        name: UIDevice.current.name,
        operatingSystem: .iOS,
        systemVersion: UIDevice.current.systemVersion)
}
#elseif os(macOS)
private func deviceInfo() -> DiscoveryHandshake.ApplicationRun.Device {
    #warning("We need a way to get an ID of the machine. Using name isn't unique enough.")
    return DiscoveryHandshake.ApplicationRun.Device(
        id: Host.current().name ?? generatedDeviceId(),
        name: Host.current().name ?? "Unknown device",
        operatingSystem: .macOS,
        systemVersion: ProcessInfo.processInfo.operatingSystemVersionString)
}
#else
#error("Device info is not implemented on this platform!")
#endif

public protocol ReceiverDiscovery {
    func discover(callback: @escaping (NetService) -> Void)

    func start()

    func stop()
}

public final class NetServiceReceiverDiscovery: ReceiverDiscovery {
    private let browser: DiscoveryServiceBrowser

    init(type: String? = nil, domain: String? = nil) {
        browser = DiscoveryServiceBrowser(serviceType: type ?? Constants.type, serviceDomain: domain ?? Constants.domain)
    }

    public func discover(callback: @escaping (NetService) -> Void) {
        browser.observeUnresolvedServices { services in
            services.forEach(callback)
        }

        start()
    }

    public func start() {
        browser.search()
    }

    public func stop() {
        browser.stop()
    }
}

public final class CaptainsLog {
    public struct Configuration {
        public var applicationRun: DiscoveryHandshake.ApplicationRun
        public var discovery: ReceiverDiscovery
        public var seed: Seed

        public init(
            applicationRun: DiscoveryHandshake.ApplicationRun,
            discovery: ReceiverDiscovery,
            seed: Seed) {

            self.applicationRun = applicationRun
            self.discovery = discovery
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
//    private let loggerService: NetService
    private let connector: DiscoveryLoggerConnector

    init(configuration: Configuration) {
        self.configuration = configuration

        connector = DiscoveryLoggerConnector(
            applicationRun: configuration.applicationRun,
            certificate: configuration.seed.certificate)

        configuration.discovery.discover { [unowned self] service in
            self.connector.connect(service: service)
                .done { connection in
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
                }
        }

    }

    func log(item: LogItem) {
        LOG.verbose("Logging item:", item)
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

        let bundle = Bundle.main

        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        let buildNumber = (bundle.infoDictionary?[kCFBundleVersionKey as String] as? String).map { "(\($0))"}
        let versionName = [version, buildNumber].compactMap { $0 }.joined(separator: " ")

        let applicationRun = DiscoveryHandshake.ApplicationRun(
            id: UUID().uuidString,
            date: Date(),
            applicationVersion: versionName,
            seedIdentifier: commonName,
            application: DiscoveryHandshake.ApplicationRun.Application(
                name: (bundle.infoDictionary?[kCFBundleNameKey as String] as? String) ?? "<Unknown>",
                identifier: (bundle.infoDictionary?[kCFBundleIdentifierKey as String] as? String) ?? "com.unknown"
            ),
            device: deviceInfo())

        return CaptainsLog.Configuration(
            applicationRun: applicationRun,
            discovery: NetServiceReceiverDiscovery(),
            seed: CaptainsLog.Configuration.Seed(
                commonName: commonName,
                certificate: certificate))
    }
}

// XXX: This is for testing purposes only. Ideas how to compile it in only when testing?
extension CaptainsLog {
    func simulateDisconnect(timeBetweenReconnect: TimeInterval) {
        configuration.discovery.stop()

        senders = []
        Thread.sleep(forTimeInterval: timeBetweenReconnect)
        configuration.discovery.start()
    }
}
