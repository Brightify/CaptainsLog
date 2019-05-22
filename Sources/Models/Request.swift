//
//  Request.swift
//  CaptainsLog
//
//  Created by Robin Krenecky on 19/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public struct Request: Codable, Equatable {
    public var method: HTTPMethod
    public var url: URL
    public var headers: [String: String]
    public var time: Date
    public var body: Data?

    public var response: Response?

    public init(method: HTTPMethod,
                url: URL,
                headers: [String: String],
                time: Date,
                body: Data?,
                response: Response?) {

        self.method = method
        self.url = url
        self.headers = headers
        self.time = time
        self.body = body
        self.response = response
    }
}

public extension Request {
    public struct Response: Codable, Equatable {
        public var time: Date
        public var code: Int
        public var headers: [String: String]
        public var body: Data?

        public init(time: Date, code: Int, headers: [String: String], body: Data?) {
            self.time = time
            self.code = code
            self.headers = headers
            self.body = body
        }
    }
}

public extension Request {
    var duration: TimeInterval? {
        guard let end = response?.time else { return nil }
        return end.timeIntervalSince(time)
    }

    var durationFormatted: String? {
        guard let end = response?.time else { return nil }
        return String(format: "%.3f", end.timeIntervalSince(time))
    }
}
