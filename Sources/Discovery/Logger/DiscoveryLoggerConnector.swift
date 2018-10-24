//
//  DiscoveryServerConnector.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation
import RxSwift

final class DiscoveryLoggerConnector {
    private let application: DiscoveryHandshake.Application

    init(application: DiscoveryHandshake.Application) {
        self.application = application
    }

    func connect(stream: TwoWayStream) -> Single<LogViewerConnection> {
        return async {
            let settings = [
                kCFStreamSSLLevel: StreamSocketSecurityLevel.tlSv1,
                kCFStreamSSLValidatesCertificateChain: false,
                kCFStreamSSLPeerName: "whoknows",
                Stream.PropertyKey.socketSecurityLevelKey: StreamSocketSecurityLevel.tlSv1,
            ] as CFDictionary

            CFReadStreamSetProperty(stream.input, CFStreamPropertyKey(kCFStreamPropertySSLSettings), settings)
            CFWriteStreamSetProperty(stream.output, CFStreamPropertyKey(kCFStreamPropertySSLSettings), settings)

            try await(stream.open().debug("server connect"))

            let policy = SecPolicyCreateSSL(false, "whoknows" as CFString)
            let streamCertificates = stream.input.property(forKey: Stream.PropertyKey(kCFStreamSSLCertificates as String))


            let logViewer = try DiscoveryHandshake(stream: stream).perform(for: self.application)

            let lastItemId = try stream.input.readDecodable(LastLogItemId.self)

            return LogViewerConnection(stream: stream, logViewer: logViewer, lastReceivedItemId: lastItemId)
        }
    }
}
