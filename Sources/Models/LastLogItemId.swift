//
//  LastLogItemId.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public enum LastLogItemId: Codable {
    case unassigned
    case assigned(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(IdType.self, forKey: .type)
        switch type {
        case .assigned:
            let value = try container.decode(String.self, forKey: .value)
            self = .assigned(value)
        case .unassigned:
            self = .unassigned
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .assigned(let id):
            try container.encode(IdType.assigned, forKey: .type)
            try container.encode(id, forKey: .value)
        case .unassigned:
            try container.encode(IdType.unassigned, forKey: .type)
        }
    }
    private enum IdType: String, Codable {
        case unassigned
        case assigned
    }
    private enum CodingKeys: CodingKey {
        case type
        case value
    }
}
