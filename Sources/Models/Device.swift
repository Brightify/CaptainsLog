//
//  Device.swift
//  NetInspector
//
//  Created by Tadeas Kriz on 19/09/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public struct Device: Codable, Hashable {
    public enum Kind: String, Codable {
        case iPhone = "iphone"
        case iPhoneSimulator = "iphonesimulator"
        case iPad = "ipad"
        case android = "android"
    }

    public var id: String
    public var name: String
    public var kind: Kind

    public init(id: String, name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}
