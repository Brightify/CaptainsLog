//
//  Application.swift
//  CaptainsLog
//
//  Created by Robin Krenecky on 12/10/2018.
//

import Foundation

public struct Application: Codable, Hashable {
    public var name: String
    public var identifier: String
    public var runs: [ApplicationRun]

    public init(name: String, identifier: String, runs: [ApplicationRun]) {
        self.name = name
        self.identifier = identifier
        self.runs = runs
    }
}
