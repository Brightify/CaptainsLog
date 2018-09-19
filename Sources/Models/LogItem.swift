//
//  LogItem.swift
//  CaptainsLog
//
//  Created by Robin Krenecky on 19/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public struct LogItem: Codable, Hashable {
    public enum Kind: Hashable {
        case request(Request)
    }

    public var id: String
    public var kind: Kind

    public var date: Date {
        switch kind {
        case .request(let request):
            return request.time
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
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .request(let request):
            try container.encode(Raw.request, forKey: .kind)
            try container.encode(request, forKey: .value)
        }
    }

    public enum Raw: String, Codable {
        case request
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }
}
