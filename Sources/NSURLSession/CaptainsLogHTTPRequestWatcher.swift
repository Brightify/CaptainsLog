//
//  CaptainsLogHTTPRequestWatcher.swift
//  Alamofire
//
//  Created by Robin Krenecky on 25/10/2018.
//

import Foundation

public final class CaptainsLogHTTPRequestWatcher {
    public var log: CaptainsLog?

    public static let instance: CaptainsLogHTTPRequestWatcher = CaptainsLogHTTPRequestWatcher()

    public static func setup(log: CaptainsLog = CaptainsLog.instance) {
        CaptainsLogHTTPRequestWatcher.instance.log = log
    }

    public static func activate() {
        CaptainsLogHTTPProtocol.activate()
    }

    public static func deactivate() {
        CaptainsLogHTTPProtocol.deactivate()
    }

    private init() {}
}
