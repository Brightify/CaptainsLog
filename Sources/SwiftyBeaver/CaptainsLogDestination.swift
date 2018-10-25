//
//  CaptainsLogDestination.swift
//  CaptainsLog-macOS
//
//  Created by Robin Krenecky on 26/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import SwiftyBeaver

public class CaptainsLogDestination: BaseDestination {
    private let log: CaptainsLog

    public init(log: CaptainsLog = CaptainsLog.instance) {
        self.log = log

        super.init()
    }
    
    public override func send(_ level: SwiftyBeaver.Level, msg: String, thread: String,
                              file: String, function: String, line: Int, context: Any?) -> String? {
        let logItem = LogItem(id: UUID().uuidString,
                              kind: .log(Log(time: Date(),
                                             level: LogLevel(rawValue: level.rawValue) ?? .unknown,
                                             message: msg,
                                             thread: thread,
                                             file: file,
                                             function: function,
                                             line: line)))

        log.log(item: logItem)

        return msg
    }
}
