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

public final class LogReceiver {
    public let itemReceived: Observable<LogItem>

    private let application: DiscoveryHandshake.Application
    private let connection: LoggerConnection

    public init(application: DiscoveryHandshake.Application, connection: LoggerConnection) {
        self.application = application
        self.connection = connection

        func readLogItem() -> Observable<LogItem> {
            return Observable.deferred {
                let item = try connection.stream.input.readDecodable(LogItem.self)

                return Observable.concat(Observable.just(item), readLogItem())
            }
        }

        itemReceived = readLogItem()
    }
}

//public final class CaptainsLogServer {
//    private let browser: DiscoveryServiceBrowser
//    private let logViewer = DiscoveryHandshake.LogViewer(
//        id: UUID().uuidString,
//        name: "A logger")
//    let connector: DiscoveryClientConnector
//
//    public init() {
//        browser = DiscoveryServiceBrowser()
//
//        connector = DiscoveryClientConnector(logViewer: logViewer)
//    }
//
//    public func start(applicationRegistered: @escaping (LoggerConnection, DiscoveryHandshake.Application) -> Void) {
//        browser.unresolvedServices
//            .concatMap { services in
//                Observable.merge(services.map(connector.connect(service: <#T##NetService#>, lastLogItemId: <#T##LastLogItemId#>)) { $0.resolved(withTimeout: 30).asObservable() }).toArray()
//            }
//
//
//
//
//        browser.didResolveServices = { services in
//            for service in services {
//                async {
//                    let connection = try await(connector.connect(service: service))
////                    connection.open()
//                    fatalError()
////                    let application = try DiscoveryHandshake().perform(on: connection, for: logger)
////
////                    print("Registered", connection, application)
////                    applicationRegistered(connection, application)
//                }
//            }
//        }
//
//        browser.search()
//    }
//}

final class LogSender {
    private let flushLock = DispatchQueue(label: "org.brightify.CaptainsLog.flushlock")
    private let queueLock = DispatchQueue(label: "org.brightify.CaptainsLog.queuelock")

    private let connection: LogViewerConnection
    private var queue: [LogItem] {
        didSet {
            flush()
        }
    }
    private var isFlushing = false

    init(connection: LogViewerConnection, queue: [LogItem]) {
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
                try! self.connection.stream.output.write(encodable: item)
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

    private let loggerService: NetService
    private let connector: DiscoveryServerConnector
    private let disposeBag = DisposeBag()

    init(info: DiscoveryHandshake.Application) {
        connector = DiscoveryServerConnector(application: info)

        loggerService = NetService.loggerService(named: "device-name", port: 11111)

        loggerService.publish()
            .flatMap(connector.connect)
            .subscribe(onNext: { [unowned self] connection in
                let initialQueue: [LogItem]
                switch connection.lastReceivedItemId {
                case .assigned(let lastItemId):
                    if let fromIndex = self.logItems.lastIndex(where: { $0.id == lastItemId }) {
                        initialQueue = Array(self.logItems[fromIndex...])
                    } else {
                        initialQueue = self.logItems
                    }
                case .unassigned:
                    initialQueue = self.logItems
                }


                let sender = LogSender(connection: connection, queue: initialQueue)
            })
            .disposed(by: disposeBag)


//        async { [weak self, deviceService] in
//            repeat {
//                let connection = try await(deviceService.acceptConnection())
//
//                async {
//                    connection.open()
//
//                    let logger = try await(DiscoveryHandshake().perform(on: connection, for: info))
//                    print("Connected to logger:", logger)
//
//                    self?.senderLock.sync {
//                        let sender = LogSender(connection: connection, queue: self?.logItems ?? [])
//
//                        self?.senders.append(sender)
//                    }
//                }
//            } while true
//        }
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
