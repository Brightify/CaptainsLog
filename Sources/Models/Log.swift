//
//  Log.swift
//  CaptainsLog-macOS
//
//  Created by Robin Krenecky on 26/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public struct Log: Codable, Equatable {
    public var time: Date
    public var level: LogLevel
    public var message: String
    public var thread: String?
    public var file: String?
    public var function: String?
    public var line: Int?

    public init(time: Date,
                level: LogLevel,
                message: String,
                thread: String?,
                file: String?,
                function: String?,
                line: Int?) {

        self.time = time
        self.level = level
        self.message = message
        self.thread = thread
        self.file = file
        self.function = function
        self.line = line
    }
}
