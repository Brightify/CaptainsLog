//
//  CaptainsLog.swift
//  CaptainsLog
//
//  Created by Robin Krenecky on 19/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public final class LogReceiver {
    private let application: DiscoveryHandshake.Application
    private let connection: DiscoveryConnection
    private let itemReceived: (LogItem) -> Void

    public init(application: DiscoveryHandshake.Application, connection: DiscoveryConnection, itemReceived: @escaping (LogItem) -> Void) {
        self.application = application
        self.connection = connection
        self.itemReceived = itemReceived

        async {
            repeat {
                let item = try connection.inputStream.readDecodable(LogItem.self)

                itemReceived(item)
            } while true
        }.debug("log receiver")
    }
}

public final class CaptainsLogServer {
    private let browser: DiscoveryServiceBrowser

    public init() {
        browser = DiscoveryServiceBrowser()
    }

    public func start(applicationRegistered: @escaping (DiscoveryConnection, DiscoveryHandshake.Application) -> Void) {
        let connector = DiscoveryClientConnector()

        let logger = DiscoveryHandshake.Logger(
            id: UUID().uuidString,
            name: "A logger")

        browser.didResolveServices = { services in
            for service in services {
                async {
                    let connection = try await(connector.connect(service: service))
                    connection.open()

                    let application = try await(DiscoveryHandshake().perform(on: connection, for: logger))

                    print("Registered", connection, application)
                    applicationRegistered(connection, application)
                }
            }
        }

        browser.search()
    }
}

final class LogSender {
    private let flushLock = DispatchQueue(label: "org.brightify.CaptainsLog.flushlock")
    private let queueLock = DispatchQueue(label: "org.brightify.CaptainsLog.queuelock")

    private let connection: DiscoveryConnection
    private var queue: [LogItem] {
        didSet {
            flush()
        }
    }
    private var isFlushing = false

    init(connection: DiscoveryConnection, queue: [LogItem]) {
        self.connection = connection
        self.queue = queue

        if !queue.isEmpty {
            flush()
        }
    }

    func push(item: LogItem) {
        print("Sender sending item:", item)
        queueLock.sync {
            queue.append(item)
        }
    }

    func flush() {
        flushLock.async {
            guard !self.isFlushing else { return }

            self.isFlushing = true

            let logQueueCopy = self.queueLock.sync { () -> [LogItem] in
                defer {
                    if !self.queue.isEmpty {
                        self.queue = []
                    }
                }
                return self.queue
            }

            guard !logQueueCopy.isEmpty else {
                self.isFlushing = false
                return
            }

            for item in logQueueCopy {
                try! self.connection.outputStream.write(encodable: item)
            }

            self.isFlushing = false
            self.flush()
        }
    }

    deinit {
        connection.close()
    }
}

final class CaptainsLog {
    private static var appInfo: DiscoveryHandshake.Application {
        return DiscoveryHandshake.Application(
            id: UUID().uuidString,
            name: "An application",
            identifier: "org.brightify.CaptainsLogTests",
            version: "0.1",
            date: Date())
    }
    static let instance = CaptainsLog(info: appInfo)

    private let senderLock = DispatchQueue(label: "org.brightify.CaptainsLog.senderlock")

    private var logItems: [LogItem] = []
    private var senders: [LogSender] = []

    private let deviceService: DiscoveryService

    init(info: DiscoveryHandshake.Application) {
        deviceService = DiscoveryService(name: "device-name", port: 11111)

        async { [weak self, deviceService] in
            repeat {
                let connection = try await(deviceService.acceptConnection())

                async {
                    connection.open()

                    let logger = try await(DiscoveryHandshake().perform(on: connection, for: info))
                    print("Connected to logger:", logger)

                    self?.senderLock.sync {
                        let sender = LogSender(connection: connection, queue: self?.logItems ?? [])

                        self?.senders.append(sender)
                    }
                }
            } while true
        }
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
