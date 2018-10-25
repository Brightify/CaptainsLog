//
//  LogLevel.swift
//  CaptainsLog-macOS
//
//  Created by Robin Krenecky on 26/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public enum LogLevel: Int, CaseIterable, Codable {
    case verbose = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case unknown = 5

    var description: String {
        switch self {
        case .verbose:
            return "Verbose"
        case .debug:
            return "Debug"
        case .info:
            return "Info"
        case .warning:
            return "Warning"
        case .error:
            return "Error"
        case .unknown:
            return "Unknown"
        }
    }
}
