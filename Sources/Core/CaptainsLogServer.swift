//
//  CaptainsLogServer.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation
import RxSwift

public final class CaptainsLogServer {
    public struct Configuration {
        public var logViewer: DiscoveryHandshake.LogViewer
        public var service: Service

        public init(logViewer: DiscoveryHandshake.LogViewer, service: Service = Service()) {
            self.logViewer = logViewer
            self.service = service
        }

        public struct Service {
            public var domain: String
            public var type: String

            public init(domain: String? = nil, type: String? = nil) {
                self.domain = domain ?? Constants.domain
                self.type = type ?? Constants.type
            }
        }
    }

    private let configuration: Configuration
    private let browser: DiscoveryServiceBrowser
    private let connector: DiscoveryLogViewerConnector

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

    public init(configuration: Configuration, identityProvider: IdentityProvider) {
        browser = DiscoveryServiceBrowser(serviceType: configuration.service.type, serviceDomain: configuration.service.domain)
        self.configuration = configuration

        let connector = DiscoveryLogViewerConnector(logViewer: configuration.logViewer, identityProvider: identityProvider)
        self.connector = connector

        let lastItemIdForApplication: (DiscoveryHandshake.Application) -> LastLogItemId = { [unowned self] application in
            self.lastReceivedItemIds[application.id, default: .unassigned]
        }

        func connect(service: NetService, retry: RetryBehavior) -> Observable<LoggerConnection> {
            return connector.connect(service: service, lastLogItemId: lastItemIdForApplication)
                .asObservable()
                .catchError { error in
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
