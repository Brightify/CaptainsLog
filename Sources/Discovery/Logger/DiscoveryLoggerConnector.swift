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
    private let certificate: SecCertificate

    init(application: DiscoveryHandshake.Application, certificate: SecCertificate) {
        self.application = application
        self.certificate = certificate
    }

    func connect(stream: TwoWayStream) -> Single<LogViewerConnection> {
        return async {
            let settings = [
                kCFStreamSSLIsServer: false,
                kCFStreamSSLLevel: StreamSocketSecurityLevel.tlSv1,
                kCFStreamSSLValidatesCertificateChain: false
            ] as CFDictionary

            enum SecurityError: Error {
                case missingTrust
                case trustEvaluationFailed
                case untrustedCertificate
            }

            do {
                stream.input.setProperty(StreamSocketSecurityLevel.tlSv1, forKey: Stream.PropertyKey.socketSecurityLevelKey)

                let success = CFReadStreamSetProperty(
                    stream.input,
                    CFStreamPropertyKey(kCFStreamPropertySSLSettings),
                    settings)
                assert(success)
            }
            do {
                stream.output.setProperty(StreamSocketSecurityLevel.tlSv1, forKey: Stream.PropertyKey.socketSecurityLevelKey)

                let success = CFWriteStreamSetProperty(
                    stream.output,
                    CFStreamPropertyKey(kCFStreamPropertySSLSettings),
                    settings)
                assert(success)
            }

            try await(stream.open().debug("server connect"))

            _ = try await(stream.hasSpaceAvailable.filter { $0 }.take(1).asSingle())


            guard let trust = safeBitCast(stream.input.property(forKey: Stream.PropertyKey(kCFStreamPropertySSLPeerTrust as String)), to: SecTrust.self) else {

                throw SecurityError.missingTrust
            }
            assert(SecTrustSetAnchorCertificates(trust, [self.certificate] as CFArray) == noErr)
            assert(SecTrustSetAnchorCertificatesOnly(trust, true) == noErr)

            var trustResult: SecTrustResultType = .invalid
            let trustEvaluationError = SecTrustEvaluate(trust, &trustResult)

            guard trustEvaluationError == errSecSuccess else {
                stream.close()
                throw SecurityError.trustEvaluationFailed
            }

            guard trustResult == .proceed || trustResult == .unspecified else {
                stream.close()
                throw SecurityError.untrustedCertificate
            }

            let logViewer = try DiscoveryHandshake(stream: stream).perform(for: self.application)

            let lastItemId = try stream.input.readDecodable(LastLogItemId.self)

            return LogViewerConnection(stream: stream, logViewer: logViewer, lastReceivedItemId: lastItemId)
        }
    }
}
