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
    private let applicationRun: DiscoveryHandshake.ApplicationRun
    private let certificate: SecCertificate

    init(applicationRun: DiscoveryHandshake.ApplicationRun, certificate: SecCertificate) {
        self.applicationRun = applicationRun
        self.certificate = certificate
    }

    func connect(service: NetService) -> Single<LogViewerConnection> {
        LOG.debug("Connect service", service)
        return async {
            LOG.debug("Will resolve service", service)
            let resolvedService = try await(service.resolved(withTimeout: 30))
            LOG.debug("Did resolve service", resolvedService)

//            LOG.debug("Will fetch txt data")
//            let okData = try await(resolvedService.txtData(containsKey: "OK", timeout: 10))
//            LOG.debug("Did fetch txt data", okData)
//
//            LOG.debug("Will decode LoggerTXT")
//            let txt = try DiscoveryLogViewerConnector.decoder.decode(LoggerTXT.self, from: okData)
//            LOG.debug("Did decode LoggerTXT", txt)

            var inputStream: InputStream?
            var outputStream: OutputStream?

            LOG.debug("Will get streams")
            precondition(resolvedService.getInputStream(&inputStream, outputStream: &outputStream), "Couldn't get streams!")
            LOG.debug("Did get streams", inputStream, outputStream)

            let stream = TwoWayStream(input: inputStream!, output: outputStream!)

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

            LOG.debug("Will open stream", stream)
            try await(stream.open().debug("server connect"))
            LOG.debug("Did open stream", stream)

            LOG.debug("Will wait for available space", stream)
            _ = try await(stream.hasSpaceAvailable.filter { $0 }.take(1).asSingle())
            LOG.debug("Did wait for available space", stream)

            guard let trust = safeBitCast(stream.input.property(forKey: Stream.PropertyKey(kCFStreamPropertySSLPeerTrust as String)), to: SecTrust.self) else {

                throw SecurityError.missingTrust
            }
            assert(SecTrustSetAnchorCertificates(trust, [self.certificate] as CFArray) == noErr)
            assert(SecTrustSetAnchorCertificatesOnly(trust, true) == noErr)

            var trustResult: SecTrustResultType = .invalid
            LOG.debug("Will evaluate trust", trust)
            let trustEvaluationError = SecTrustEvaluate(trust, &trustResult)
            LOG.debug("Did evaluate trust", trustEvaluationError, trustResult)

            guard trustEvaluationError == errSecSuccess else {
                stream.close()
                throw SecurityError.trustEvaluationFailed
            }

            guard trustResult == .proceed || trustResult == .unspecified else {
                stream.close()
                throw SecurityError.untrustedCertificate
            }

            LOG.debug("Will perform handshake")
            let logViewer = try DiscoveryHandshake(stream: stream).perform(for: self.applicationRun)
            LOG.debug("Did perform handshake", logViewer)

            LOG.debug("Will read last item id")
            let lastItemId = try stream.input.readDecodable(LastLogItemId.self)
            LOG.debug("Did read last item id", lastItemId)

            LOG.debug("LogViewerConnection created", resolvedService, stream, logViewer, lastItemId)
            return LogViewerConnection(service: resolvedService, stream: stream, logViewer: logViewer, lastReceivedItemId: lastItemId)
        }
    }
}
