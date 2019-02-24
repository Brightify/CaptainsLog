//
//  CaptainsLogServer.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public protocol CaptainsLogServerDelegate: AnyObject {
    func server(_ server: CaptainsLogServer, didAcceptConnection connection: LoggerConnection)

    func server(_ server: CaptainsLogServer, didReceive item: LogItem, connection: LoggerConnection)
}

extension CaptainsLogServerDelegate {
    public func server(_ server: CaptainsLogServer, didAcceptConnection connection: LoggerConnection) { }

    public func server(_ server: CaptainsLogServer, didReceive item: LogItem, connection: LoggerConnection) { }
}

public final class CaptainsLogServer: NSObject {
    public struct Configuration {
        public var logViewer: DiscoveryHandshake.LogReceiver
        public var service: Service

        public init(logViewer: DiscoveryHandshake.LogReceiver, service: Service) {
            self.logViewer = logViewer
            self.service = service
        }

        public struct Service {
            public var name: String
            public var domain: String
            public var type: String
            public var port: Int

            public init(name: String, domain: String? = nil, type: String? = nil, port: Int? = nil) {
                self.name = name
                self.domain = domain ?? Constants.domain
                self.type = type ?? Constants.type
                self.port = port ?? Constants.port
            }
        }
    }

    private let configuration: Configuration
    private let connector: DiscoveryLogViewerConnector

//    private let lastReceivedItemIdsSubject = BehaviorSubject<[String: LastLogItemId]>(value: [:])
    private var lastReceivedItemIds: [String: LastLogItemId] = [:] {
        didSet {
//            lastReceivedItemIdsSubject.onNext(lastReceivedItemIds)
        }
    }

//    private let newLoggerConnectionSubject = PublishSubject<LoggerConnection>()
//    public var newLoggerConnection: Observable<LoggerConnection> {
//        return newLoggerConnectionSubject
//    }
//
//    private let itemReceivedSubject = PublishSubject<(connection: LoggerConnection, item: LogItem)>()
//    public var itemReceived: Observable<(connection: LoggerConnection, item: LogItem)> {
//        return itemReceivedSubject
//    }

    public weak var delegate: CaptainsLogServerDelegate?
    private let delegateQueue = DispatchQueue.main

    private var logReceivers: [String: LogReceiver] = [:]
    let logReceiverService: NetService
    private let disposeBag = DisposeBag()

    public init(configuration: Configuration, identityProvider: IdentityProvider) {
        self.configuration = configuration

        self.connector = DiscoveryLogViewerConnector(logViewer: configuration.logViewer, identityProvider: identityProvider)

        logReceiverService = NetService.loggerService(
            named: configuration.service.name,
            identifier: "not important",
            domain: configuration.service.domain,
            type: configuration.service.type,
            port: configuration.service.port)

        super.init()

        logReceiverService.schedule(in: .main, forMode: .default)
        logReceiverService.delegate = self
//



//        let newLoggerConnection = logReceiverService.publish()
//            .flatMap {
//                connect(stream: $0, retry: .default)
//            }
//            .share()


//        let newLoggerConnection = browser.unresolvedServices
//            .withLatestFrom(lastReceivedItemIdsSubject) { services, lastItemIds in
//                Observable.concat(services.map {
//                    connect(service: $0, retry: .default)
//                })
//            }
//            .concat()
//            .share()



//        newLoggerConnection.subscribe(newLoggerConnectionSubject).disposed(by: disposeBag)

//        newLoggerConnection
//            .flatMap { connection in
//                receive(connection: connection, retry: .default)
//            }
//            .do(onNext: { [unowned self] connection, item in
//                self.lastReceivedItemIds[connection.applicationRun.id] = .assigned(item.id)
//            })
//            .subscribe(itemReceivedSubject)
//            .disposed(by: disposeBag)
    }

    deinit {
        print("whaaat")
        logReceiverService.delegate = nil
    }

    public func start() {
        logReceiverService.publish(options: .listenForConnections)
    }

    public func stop() {
        logReceiverService.stop()
    }

    private func callDelegate(call: @escaping (CaptainsLogServerDelegate) -> Void) {
        guard let delegate = delegate else { return }
        delegateQueue.sync { call(delegate) }
    }
//
//    public func startSearching() {
//        browser.search()
//    }
}

// MARK:- Connect services
extension CaptainsLogServer {
    private func didAcceptConnection(stream: TwoWayStream) {
        async {
            let connection = try await(self.connect(stream: stream, retry: .default))

            self.callDelegate { $0.server(self, didAcceptConnection: connection) }

            self.receive(connection: connection, retry: .default)
        }
    }

    private func connect(stream: TwoWayStream, retry: RetryBehavior) -> Promise<LoggerConnection> {
        return connector.connect(stream: stream, lastLogItemId: { [unowned self] application in
            self.lastReceivedItemIds[application.id, default: .unassigned]
        })

        #warning("FIXME This reconnect has to be on Logger side!")
//            .catchError { error in
//                    guard retry.canRetry else {
//                        return .error(error)
//                    }
//
//                    return connect(stream: stream, retry: retry.next())
//                        .delaySubscription(retry.delay, scheduler: MainScheduler.instance)
//            }
    }
}

// MARK:- Receive items
extension CaptainsLogServer: LogReceiverDelegate {
    #warning("FIXME: This function creates a retain cycle (usage of `self.lastReceivedItemIds`). This has to be corrected")
    private func receive(connection: LoggerConnection, retry: RetryBehavior) {
        let receiver = LogReceiver(connection: connection, queue: Queue.work)
        receiver.delegate = self
        logReceivers[connection.applicationRun.id] = receiver

        receiver.startReceiving()

//        return receiver.itemReceived
//            .map { (connection: receiver.connection, item: $0) }
        #warning("FIXME This reconnect has to be on Logger side!")
//            .catchError { error in
//                    guard retry.canRetry else {
//                        // This means the stream got disconnected for good. We can do some cleanup here later.
//                        return .error(error)
//                    }
//                    return connect(stream: connection.stream, retry: retry.next())
//                        .flatMap { newConnection -> Observable<LoggerConnection> in
//                            guard newConnection.applicationRun.id == connection.applicationRun.id else {
//                                return .empty()
//                            }
//                            return .just(newConnection)
//                        }
//                        .delaySubscription(retry.delay, scheduler: MainScheduler.instance)
//                        .flatMap { connection in
//                            receive(connection: connection, retry: retry.next())
//                    }
//            }
    }

    public func logReceiver(_ receiver: LogReceiver, received item: LogItem) {
        let connection = receiver.connection
        lastReceivedItemIds[connection.applicationRun.id] = .assigned(item.id)

        callDelegate { $0.server(self, didReceive: item, connection: connection) }
    }

    public func logReceiver(_ receiver: LogReceiver, errored error: Error) {
        #warning("FIXME We should check the error and decide if stopping receiving is the right call")
        receiver.stopReceiving()
        logReceivers.removeValue(forKey: receiver.connection.applicationRun.id)
    }
}

// MARK:- NetServiceDelegate
extension CaptainsLogServer: NetServiceDelegate {
//    private let didAcceptConnection: (TwoWayStream) -> Void
//    init(didAcceptConnection: @escaping (TwoWayStream) -> Void) {
//        self.didAcceptConnection = didAcceptConnection
//    }

    @objc
    public func netService(_ sender: NetService, didAcceptConnectionWith inputStream: InputStream, outputStream: OutputStream) {
        LOG.verbose(#function, sender)
        didAcceptConnection(stream: TwoWayStream(input: inputStream, output: outputStream))
    }

    @objc
    public func netServiceWillPublish(_ sender: NetService) {
        LOG.verbose(#function, sender)
    }

    @objc
    public func netServiceDidPublish(_ sender: NetService) {
        LOG.verbose(#function, sender)
        sender.setTXTRecord(sender.txtRecordData())
    }

    @objc
    public func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        LOG.verbose(#function, sender, errorDict)
    }
}
