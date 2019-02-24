//
//  Logging.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 28/10/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

private var logging: Logging = PrintLogging(limit: .error)

internal enum LOG {
    static func verbose(_ items: Any..., file: String = #file, function: String = #function, line: Int = #line) {
        logging.verbose(items, file: file, function: function, line: line)
    }

    static func debug(_ items: Any..., file: String = #file, function: String = #function, line: Int = #line) {
        logging.debug(items, file: file, function: function, line: line)
    }

    static func info(_ items: Any..., file: String = #file, function: String = #function, line: Int = #line) {
        logging.info(items, file: file, function: function, line: line)
    }

    static func warning(_ items: Any..., file: String = #file, function: String = #function, line: Int = #line) {
        logging.warning(items, file: file, function: function, line: line)
    }

    static func error(_ items: Any..., file: String = #file, function: String = #function, line: Int = #line) {
        logging.error(items, file: file, function: function, line: line)
    }
}

public protocol Logging {
    func verbose(_ items: [Any], file: String, function: String, line: Int)

    func debug(_ items: [Any], file: String, function: String, line: Int)

    func info(_ items: [Any], file: String, function: String, line: Int)

    func warning(_ items: [Any], file: String, function: String, line: Int)

    func error(_ items: [Any], file: String, function: String, line: Int)
}

extension Logging {
    public func activate() {
        logging = self
    }
}

public final class PrintLogging: Logging {
    public enum Level: Int {
        case verbose = 0
        case debug = 1
        case info = 2
        case warning = 3
        case error = 4
        case disable = 5
    }

    private let limit: Level

    public init(limit: Level) {
        self.limit = limit
    }

    public func verbose(_ items: [Any], file: String, function: String, line: Int) {
        guard canLog(level: .verbose) else { return }
        logPrint(items: ["💜 V: "] + items, file: file, function: function, line: line)
    }

    public func debug(_ items: [Any], file: String, function: String, line: Int) {
        guard canLog(level: .debug) else { return }
        logPrint(items: ["💚 D: "] + items, file: file, function: function, line: line)
    }

    public func info(_ items: [Any], file: String, function: String, line: Int) {
        guard canLog(level: .info) else { return }
        logPrint(items: ["💙 I: "] + items, file: file, function: function, line: line)
    }

    public func warning(_ items: [Any], file: String, function: String, line: Int) {
        guard canLog(level: .warning) else { return }
        logPrint(items: ["💛 W: "] + items, file: file, function: function, line: line)
    }

    public func error(_ items: [Any], file: String, function: String, line: Int) {
        guard canLog(level: .error) else { return }
        logPrint(items: ["💔 E: "] + items, file: file, function: function, line: line)
    }

    private func logPrint(items: [Any], file: String, function: String, line: Int) {
        print(items.map { String(describing: $0) }.joined(separator: ", "))
        if limit == .verbose {
            print("\(function) at \(file):\(line)")
        }
    }

    private func canLog(level: Level) -> Bool {
        return level.rawValue >= limit.rawValue
    }
}
