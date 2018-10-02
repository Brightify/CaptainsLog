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

    let connection: LoggerConnection

    public init(connection: LoggerConnection) {
        self.connection = connection

        var remainingRetries = 10
        var lastRetryDelay = 0.2

        func readLogItem() -> Observable<LogItem> {
            return Observable
                .deferred {
                    let item = try connection.stream.input.readDecodable(LogItem.self)

                    return Observable.concat(Observable.just(item), readLogItem())
                }
        }

        itemReceived = readLogItem()
    }
}

public final class CaptainsLogServer {
    private let browser: DiscoveryServiceBrowser
    private let logViewer: DiscoveryHandshake.LogViewer
    private let connector: DiscoveryClientConnector

    private let lastReceivedItemIdsSubject = BehaviorSubject<[String: LastLogItemId]>(value: [:])
    private var lastReceivedItemIds: [String: LastLogItemId] = [:] {
        didSet {
            lastReceivedItemIdsSubject.onNext(lastReceivedItemIds)
        }
    }

    private let newLoggerConnectionSubject = PublishSubject<LoggerConnection>()
    public var newLoggerConnection: Observable<LoggerConnection> {
        return newLoggerConnectionSubject
    }

    private let itemReceivedSubject = PublishSubject<(connection: LoggerConnection, item: LogItem)>()
    public var itemReceived: Observable<(connection: LoggerConnection, item: LogItem)> {
        return itemReceivedSubject
    }

    private var logReceivers: [String: LogReceiver] = [:]

    private let disposeBag = DisposeBag()

    public init(logViewer: DiscoveryHandshake.LogViewer) {
        browser = DiscoveryServiceBrowser()
        self.logViewer = logViewer

        let connector = DiscoveryClientConnector(logViewer: logViewer)
        self.connector = connector

        struct RetryBehavior {
            private let nextDelay: (TimeInterval) -> TimeInterval
            private var remaining: Int
            let delay: TimeInterval

            var canRetry: Bool {
                return remaining > 0
            }

            init(retries: Int, initialDelay: TimeInterval, nextDelay: @escaping (TimeInterval) -> TimeInterval) {
                self.remaining = retries
                self.delay = initialDelay
                self.nextDelay = nextDelay
            }

            func next() -> RetryBehavior {
                return RetryBehavior(
                    retries: remaining - 1,
                    initialDelay: nextDelay(delay),
                    nextDelay: nextDelay)
            }

            static let `default`: RetryBehavior = RetryBehavior(retries: 10, initialDelay: 0.1, nextDelay: { $0 * 2 })
        }

        let lastItemIdForApplication: (DiscoveryHandshake.Application) -> LastLogItemId = { [unowned self] application in
            self.lastReceivedItemIds[application.id, default: .unassigned]
        }

        func connect(service: NetService, retry: RetryBehavior) -> Observable<LoggerConnection> {
            return connector.connect(service: service, lastLogItemId: lastItemIdForApplication)
                .asObservable()
                .catchError { error in
                    guard error is TwoWayStream.OpenError else {
                        assertionFailure("An unknown error happened: \(error)")
                        return .empty()
                    }

                    guard retry.canRetry else {
                        return .error(error)
                    }

                    return connect(service: service, retry: retry.next())
                        .delaySubscription(retry.delay, scheduler: MainScheduler.instance)
            }
        }

        let newLoggerConnection = browser.unresolvedServices
            .withLatestFrom(lastReceivedItemIdsSubject) { services, lastItemIds in
                Observable.concat(services.map {
                    connect(service: $0, retry: .default)
                })
            }
            .concat()
            .share()

        // FIXME This function creates a retain cycle (usage of `self.lastReceivedItemIds`). This has to be corrected
        func receive(connection: LoggerConnection, retry: RetryBehavior) -> Observable<(connection: LoggerConnection, item: LogItem)> {
            let receiver = LogReceiver(connection: connection)

            logReceivers[connection.application.id] = receiver

            return receiver.itemReceived
                .map { (connection: receiver.connection, item: $0) }
                .catchError { error in
                    guard retry.canRetry else {
                        // This means the stream got disconnected for good. We can do some cleanup here later.
                        return .error(error)
                    }

                    return connect(service: connection.service, retry: retry.next())
                        .delaySubscription(retry.delay, scheduler: MainScheduler.instance)
                        .flatMap { connection in
                            receive(connection: connection, retry: retry.next())
                        }
                }
        }

        newLoggerConnection.subscribe(newLoggerConnectionSubject).disposed(by: disposeBag)

        newLoggerConnection
            .flatMap { connection in
                receive(connection: connection, retry: .default)
            }
            .do(onNext: { [unowned self] connection, item in
                self.lastReceivedItemIds[connection.application.id] = .assigned(item.id)
            })
            .subscribe(itemReceivedSubject)
            .disposed(by: disposeBag)
    }

    public func startSearching() {
        browser.search()
    }
}

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
