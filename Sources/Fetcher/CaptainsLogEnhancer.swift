//
//  CaptainsLogEnhancer.swift
//  CaptainsLog
//
//  Created by Robin Krenecky on 19/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation
import protocol Fetcher.RequestEnhancer
import protocol Fetcher.RequestModifier
import struct Fetcher.Request
import struct Fetcher.Response
import class DataMapper.SupportedType

internal struct NetInspectorTimestamp: RequestModifier {
    internal let time: Date
    internal let uuid: UUID
}

public final class CaptainsLogEnhancer: RequestEnhancer {
    private let log: CaptainsLog

    public init() {
//        self.captainsLogBaseURL = components.url!
//        self.applicationId = Bundle.main.infoDictionary![kCFBundleNameKey as String] as! String
//        self.uuid = UUID().uuidString

//        try! register()

        log = CaptainsLog.instance
    }

    public func enhance(request: inout Fetcher.Request) {
        request.modifiers.append(NetInspectorTimestamp(time: Date(), uuid: UUID()))
    }

    public func deenhance(response: inout Fetcher.Response<SupportedType>) {
        print("Deenhancing log")
        guard let timestamp = response.request.modifiers.compactMap({ $0 as? NetInspectorTimestamp }).first else { return }

        let allRequestHeaders = response.request.allHTTPHeaderFields?.compactMap { key, value -> (key: String, value: String)? in
            return (key: key, value: value)
        } ?? []
        let requestHeaders = Dictionary(allRequestHeaders, uniquingKeysWith: { $1 })

        let allResponseHeaders = response.rawResponse?.allHeaderFields.compactMap { key, value -> (key: String, value: String)? in
            guard let keyString = key as? String, let valueString = value as? String else { return nil }
            return (key: keyString, value: valueString)
            } ?? []
        let responseHeaders = Dictionary(allResponseHeaders, uniquingKeysWith: { $1 })

        let logItem = LogItem(
            id: UUID().uuidString,
            kind: .request(Request(method: HTTPMethod(rawValue: response.request.httpMethod.rawValue)!,
                                   url: response.request.url ?? URL(fileURLWithPath: ""),
                                   headers: requestHeaders,
                                   time: timestamp.time,
                                   body: response.request.httpBody ?? Data(),
                                   response: Request.Response(time: Date(),
                                                              code: response.rawResponse?.statusCode ?? 0,
                                                              headers: responseHeaders,
                                                              body: response.rawData ?? Data()))))

        log.log(item: logItem)
//        try? post(to: "api/runs/\(uuid)/logItems", value: logItem)
    }

//    private func register() throws {
//        let appRun = ApplicationRun(
//            id: uuid,
//            name: Bundle.main.infoDictionary![kCFBundleNameKey as String] as! String,
//            identifier: Bundle.main.bundleIdentifier!,
//            version: Bundle.main.infoDictionary![kCFBundleVersionKey as String] as! String,
//            date: Date()
//        )
//
//        try post(to: "api/runs", value: appRun)
//    }
}
