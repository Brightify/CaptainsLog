//
//  Logging.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 28/10/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

internal var LOG: Logging = PrintLogging(limit: .error)

public protocol Logging {
    func verbose(_ items: Any...)

    func debug(_ items: Any...)

    func info(_ items: Any...)

    func warning(_ items: Any...)

    func error(_ items: Any...)
}

extension Logging {
    public func activate() {
        LOG = self
    }
}

final class PrintLogging: Logging {
    enum Level: Int {
        case verbose = 0
        case debug = 1
        case info = 2
        case warning = 3
        case error = 4
        case disable = 5
    }

    private let limit: Level

    init(limit: Level) {
        self.limit = limit
    }

    func verbose(_ items: Any...) {
        guard canLog(level: .verbose) else { return }
        print(["V: "] + items)
    }

    func debug(_ items: Any...) {
        guard canLog(level: .debug) else { return }
        print(["D: "] + items)
    }

    func info(_ items: Any...) {
        guard canLog(level: .info) else { return }
        print(["I: "] + items)
    }

    func warning(_ items: Any...) {
        guard canLog(level: .warning) else { return }
        print(["W: "] + items)
    }

    func error(_ items: Any...) {
        guard canLog(level: .error) else { return }
        print(["E: "] + items)
    }

    func canLog(level: Level) -> Bool {
        return level.rawValue >= limit.rawValue
    }
}
