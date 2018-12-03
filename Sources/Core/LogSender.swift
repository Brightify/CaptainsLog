//
//  LogSender.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation
import RxSwift

final class LogSender {

    private let disconnectedSubject = PublishSubject<Void>()
    var disconnected: Observable<Void> {
        return disconnectedSubject
    }

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
        LOG.debug("Sender sending item:", item)
        queueLock.sync {
            queue.append(item)
        }
    }

    private func flush() {
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
                do {
                    try RetryBehavior.short.retry {
                        try self.connection.stream.output.write(encodable: item)
                    }
                } catch {
                    self.disconnectedSubject.onNext(())
                }
            }

            self.isFlushing = false
            self.flush()
        }
    }

    deinit {
        connection.close()
    }
}
