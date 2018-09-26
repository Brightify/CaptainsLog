//
//  LogLevel.swift
//  CaptainsLog-macOS
//
//  Created by Robin Krenecky on 26/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public enum LogLevel: Int, Codable {
    case verbose = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
}
