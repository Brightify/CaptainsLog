//
//  Token.swift
//  CaptainsLog
//
//  Created by Robin Krenecky on 19/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public struct Token: Codable, Hashable {
    public var token: String

    public init(token: String) {
        self.token = token
    }
}
