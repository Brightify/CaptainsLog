//
//  CaptainsLogCLLogger.swift
//  CaptainsLog-macOS
//
//  Created by Robin Krenecky on 25/10/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation
import CocoaLumberjack

public final class CaptainsLogCLLogger: DDAbstractLogger {
    private let log: CaptainsLog

    public init(log: CaptainsLog = CaptainsLog.instance) {
        self.log = log

        super.init()
    }
    
    public override func log(message logMessage: DDLogMessage) {
        let logItem = LogItem(id: UUID().uuidString,
                              kind: .log(Log(time: Date(),
                                             level: logMessage.flag.logLevel,
                                             message: logMessage.message,
                                             thread: logMessage.threadName,
                                             file: logMessage.file,
                                             function: logMessage.function,
                                             line: Int(logMessage.line))))

        log.log(item: logItem)
    }
}

private extension DDLogFlag {
    var logLevel: LogLevel {
        switch self.rawValue {
        case (1 << 0):
            return .error
        case (1 << 1):
            return .warning
        case (1 << 2):
            return .info
        case (1 << 3):
            return .debug
        case (1 << 4):
            return .verbose
        default:
            return .unknown
        }
    }
}
