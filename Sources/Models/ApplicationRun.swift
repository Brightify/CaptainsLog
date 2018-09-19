//
//  ApplicationRun.swift
//  CaptainsLog
//
//  Created by Robin Krenecky on 19/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public struct ApplicationRun: Codable, Hashable {
    public var id: String
    public var name: String
    public var identifier: String
    public var version: String
    public var date: Date

    public init(id: String, name: String, identifier: String, version: String, date: Date) {
        self.id = id
        self.name = name
        self.identifier = identifier
        self.version = version
        self.date = date
    }
}
