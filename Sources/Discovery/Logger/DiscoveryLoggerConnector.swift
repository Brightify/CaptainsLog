//
//  DiscoveryServerConnector.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

final class DiscoveryLoggerConnector {
    private let applicationRun: DiscoveryHandshake.ApplicationRun
    private let certificate: SecCertificate

    init(applicationRun: DiscoveryHandshake.ApplicationRun, certificate: SecCertificate) {
        self.applicationRun = applicationRun
        self.certificate = certificate
    }

    func connect(service: NetService) -> Promise<LogViewerConnection> {
        LOG.debug("Connect service", service)

        enum SecurityError: Error {
            case missingTrust
            case trustEvaluationFailed
            case untrustedCertificate
        }

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

            LOG.debug("Will open stream", stream)
            try await(stream.open().debug("server connect"))
            LOG.debug("Did open stream", stream)

            LOG.debug("Will wait for available space", stream)
            try await(Promises.blockUntil { stream.hasSpaceAvailable })
            LOG.debug("Did wait for available space", stream)

            LOG.debug("Will perform handshake")
            let logViewer = try DiscoveryHandshake(stream: stream).perform(for: self.applicationRun)
            LOG.debug("Did perform handshake", logViewer)

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

            let context: SSLContext = SSLCreateContext(kCFAllocatorDefault, SSLProtocolSide.clientSide, SSLConnectionType.streamType)!
            SSLSetSessionOption(context, SSLSessionOption.breakOnServerAuth, true)
//            let wcontext: SSLContext = SSLCreateContext(kCFAllocatorDefault, SSLProtocolSide.clientSide, SSLConnectionType.streamType)!
//            SSLSetCertificate(context, [identity] as CFArray)

//            SSLSetCertificate(<#T##context: SSLContext##Security.SSLContext#>, <#T##certRefs: CFArray?##CoreFoundation.CFArray?#>)

            LOG.debug("Will set context")
            try stream.set(context: context)
            LOG.debug("Did set context")


            LOG.debug("Will wait for available space", stream)
            try await(Promises.blockUntil { stream.hasSpaceAvailable })
            LOG.debug("Did wait for available space", stream)

            let hasShookHands = Promises.blockUntil {
                var sessionState = SSLSessionState.idle
                SSLGetSessionState(context, &sessionState)
                return sessionState != SSLSessionState.handshake
            }

            LOG.debug("Will handshake", stream)
            try await(hasShookHands)
            LOG.debug("Did handshake", stream)

            var maybeTrust: SecTrust?
            SSLCopyPeerTrust(context, &maybeTrust)

            guard let trust = maybeTrust else { // safeBitCast(stream.input.property(forKey: Stream.PropertyKey(kCFStreamPropertySSLPeerTrust as String)), to: SecTrust.self) else {
                LOG.error("No trust found in context!")
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

            LOG.debug("Will read last item id")
            let lastItemId = try stream.input.readDecodable(LastLogItemId.self)
            LOG.debug("Did read last item id", lastItemId)

            LOG.debug("LogViewerConnection created", resolvedService, stream, logViewer, lastItemId)
            return LogViewerConnection(service: resolvedService, stream: stream, logViewer: logViewer, lastReceivedItemId: lastItemId)
        }.debug("LoggerConnection")
    }
}
