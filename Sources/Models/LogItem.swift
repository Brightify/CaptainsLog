//
//  LogItem.swift
//  CaptainsLog
//
//  Created by Robin Krenecky on 19/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public struct LogItem: Codable, Equatable {
    public enum Kind: Equatable {
        case request(Request)
        case log(Log)
    }

    public var id: String
    public var kind: Kind

    public var date: Date {
        switch kind {
        case .request(let request):
            return request.time
        case .log(let log):
            return log.time
        }
    }

    public init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

extension LogItem.Kind: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Raw.self, forKey: .kind)

        switch kind {
        case .request:
            let request = try container.decode(Request.self, forKey: .value)
            self = .request(request)
        case .log:
            let log = try container.decode(Log.self, forKey: .value)
            self = .log(log)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .request(let request):
            try container.encode(Raw.request, forKey: .kind)
            try container.encode(request, forKey: .value)
        case .log(let log):
            try container.encode(Raw.log, forKey: .kind)
            try container.encode(log, forKey: .value)
        }
    }

    public enum Raw: String, Codable {
        case request
        case log
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }
}

public enum LogLevel: Int, Codable, Equatable {
    case verbose = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
}

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
