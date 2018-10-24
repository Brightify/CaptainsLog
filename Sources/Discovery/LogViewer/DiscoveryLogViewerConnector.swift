//
//  DiscoveryClientConnector.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation
import RxSwift

public final class CertificateManager {
    public struct Certificate {
        let id: String
        let privateKey: SecKey
        let identity: SecIdentity
        let certificate: SecCertificate
    }

    public var keys: [String: Certificate] = [:]

    public func identity(forId identifier: String) -> SecIdentity? {
        guard let certificate = keys[identifier] else { return nil }
        return certificate.identity
//        SecIdentity


    }

    func load(data: Data, password: String) {
        let options = [kSecImportExportPassphrase: password] as CFDictionary

        var items: CFArray?
        let importError = SecPKCS12Import(data as CFData, options, &items)
        assert(importError == noErr)

        let identityDictionary = unsafeBitCast(CFArrayGetValueAtIndex(items, 0), to: CFDictionary.self) as! [String: Any]
        let keyId = identityDictionary[kSecImportItemLabel as String] as! String
        let identity = identityDictionary[kSecImportItemIdentity as String] as! SecIdentity

        var privateKey: SecKey?
        SecIdentityCopyPrivateKey(identity, &privateKey)

        var certificate: SecCertificate?
        SecIdentityCopyCertificate(identity, &certificate)

//        var publicKey: SecKey?

        let c = Certificate(
            id: keyId,
            privateKey: privateKey!,
            identity: identity,
            certificate: certificate!)

        keys[keyId] = c
    }

    func load(url: URL, password: String) throws {
        try load(data: Data(contentsOf: url), password: password)
    }
}

final class DiscoveryLogViewerConnector {
    private static let decoder = JSONDecoder()

    private let logViewer: DiscoveryHandshake.LogViewer
    private let certificateManager: CertificateManager

    init(logViewer: DiscoveryHandshake.LogViewer, certificateManager: CertificateManager) {
        self.logViewer = logViewer
        self.certificateManager = certificateManager
    }

    func connect(service: NetService, lastLogItemId: @escaping (DiscoveryHandshake.Application) -> LastLogItemId) -> Single<LoggerConnection> {
        return async {
            let resolvedService = try await(service.resolved(withTimeout: 30))

            let txtRecords = try await(resolvedService.txtData(containsKey: "OK", timeout: 10))

            guard let okData = txtRecords["OK"] else {
                fatalError("Error in txtData resolution! We should always have the key available if we got a response from the `txtData` method!")
            }
            let txt = try DiscoveryLogViewerConnector.decoder.decode(LoggerTXT.self, from: okData)

            var inputStream: InputStream?
            var outputStream: OutputStream?

            precondition(resolvedService.getInputStream(&inputStream, outputStream: &outputStream), "Couldn't get streams!")

            let stream = TwoWayStream(input: inputStream!, output: outputStream!)

            if let identity = self.certificateManager.identity(forId: txt.identifier) {
                stream.input.setProperty(StreamSocketSecurityLevel.tlSv1, forKey: Stream.PropertyKey.socketSecurityLevelKey)

                let success = CFReadStreamSetProperty(
                    stream.input,
                    CFStreamPropertyKey(kCFStreamPropertySSLSettings),
                    [
                        kCFStreamSSLIsServer: true,
                        kCFStreamSSLCertificates: [identity],
                        kCFStreamSSLValidatesCertificateChain: false,
                    ] as CFDictionary)
                assert(success)

                stream.output.setProperty(StreamSocketSecurityLevel.tlSv1, forKey: Stream.PropertyKey.socketSecurityLevelKey)
            }

            try await(stream.open())

            let application = try DiscoveryHandshake(stream: stream).perform(for: self.logViewer)

            try stream.output.write(encodable: lastLogItemId(application))

            return LoggerConnection(service: resolvedService, stream: stream, application: application)
        }
    }

}
