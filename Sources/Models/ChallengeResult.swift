//
//  ChallengeResult.swift
//  CaptainsLog
//
//  Created by Robin Krenecky on 19/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public struct ChallengeResult: Codable, Hashable {
    public var pin: String

    public init(pin: String) {
        self.pin = pin
    }
}
