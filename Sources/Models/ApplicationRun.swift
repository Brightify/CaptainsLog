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
    public var applicationVersion: String
    public var date: Date

    public init(id: String, applicationVersion: String, date: Date) {
        self.id = id
        self.applicationVersion = applicationVersion
        self.date = date
    }
}
