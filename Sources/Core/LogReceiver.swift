//
//  LogReceiver.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public protocol LogReceiverDelegate: AnyObject {
    func logReceiver(_ receiver: LogReceiver, received item: LogItem)

    func logReceiver(_ receiver: LogReceiver, errored error: Error)
}

extension LogReceiverDelegate {
    public func logReceiver(_ receiver: LogReceiver, received item: LogItem) { }

    public func logReceiver(_ receiver: LogReceiver, errored error: Error) { }
}

public final class LogReceiver {
    public weak var delegate: LogReceiverDelegate?

//    public let itemReceived: Observable<LogItem>

    let connection: LoggerConnection
    private let queue: DispatchQueue
    private(set) var isReceiving: Bool = false

    public init(connection: LoggerConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    public func startReceiving() {
        isReceiving = true

        queue.async { [unowned self] in
            self.receive()
        }
    }

    public func stopReceiving() {
        isReceiving = false
    }

    private func receive() {
        while (isReceiving) {
            do {
                try await(Promises.blockUntil { self.connection.stream.hasBytesAvailable })
                let item = try connection.stream.input.readDecodable(LogItem.self)

                LOG.verbose("Log receiver \(self) received: \(item)")
                delegate?.logReceiver(self, received: item)
            } catch {
                LOG.verbose("Log receiver \(self) error: \(error)")
                delegate?.logReceiver(self, errored: error)
            }
        }
    }

    deinit {
        stopReceiving()
    }
}
