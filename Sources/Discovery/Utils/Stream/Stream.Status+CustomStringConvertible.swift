//
//  Stream.Status+CustomStringConvertible.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

extension Stream.Status: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notOpen:
            return "not open"
        case .opening:
            return "opening"
        case .open:
            return "open"
        case .reading:
            return "reading"
        case .writing:
            return "writing"
        case .atEnd:
            return "at end"
        case .closed:
            return "closed"
        case .error:
            return "error"
        }
    }
}
