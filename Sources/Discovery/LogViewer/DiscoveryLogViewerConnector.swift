//
//  DiscoveryClientConnector.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation
import RxSwift

public protocol IdentityProvider: AnyObject {
    func identity(forId identifier: String) -> SecIdentity?
}

public struct ImportedIdentity {
    public let id: String
    public let privateKey: SecKey
    public let identity: SecIdentity
    public let certificate: SecCertificate

    public static func identities(inP12 data: Data, password: String) throws -> [ImportedIdentity] {
        let options = [kSecImportExportPassphrase: password] as CFDictionary

        let items = try SecPKCS12Import(data, options)

        return items.compactMap { item in
            guard let identityDictionary = safeBitCast(item, to: CFDictionary.self) as? [String: Any] else {
                LOG.error("Can't cast \(item) to identity dictionary [String: Any]")
                return nil
            }
            guard let keyId = identityDictionary[kSecImportItemLabel as String] as? String else {
                LOG.error("Identity dictionary doesn't contain label.", identityDictionary)
                return nil
            }
            guard let identity = safeBitCast(identityDictionary[kSecImportItemIdentity as String], to: SecIdentity.self) else {
                LOG.error("Identity not found in identity dictionary.", identityDictionary)
                return nil
            }
            guard let privateKey = identity.privateKey else {
                LOG.error("Private key not in identity.", identity)
                return nil
            }
            guard let certificate = identity.certificate else {
                LOG.error("Certificate not in identity.", identity)
                return nil
            }
            return ImportedIdentity(
                id: keyId,
                privateKey: privateKey,
                identity: identity,
                certificate: certificate)
        }
    }
}

public protocol SafeBitCastable {
    static var cfTypeId: CFTypeID { get }
}

extension CFDictionary: SafeBitCastable {
    public static let cfTypeId: CFTypeID = CFDictionaryGetTypeID()
}

extension SecIdentity: SafeBitCastable {
    public static let cfTypeId: CFTypeID = SecIdentityGetTypeID()
}

extension SecTrust: SafeBitCastable {
    public static let cfTypeId: CFTypeID = SecTrustGetTypeID()
}

extension SecKey: SafeBitCastable {
    public static let cfTypeId: CFTypeID = SecKeyGetTypeID()
}

public func safeBitCast<T, U: SafeBitCastable>(_ x: T, to type: U.Type) -> U? {
    let typeId = CFGetTypeID(x as CFTypeRef)
    guard typeId == type.cfTypeId else { return nil }

    return withUnsafePointer(to: x) {
        $0.withMemoryRebound(to: type, capacity: 1) {
            return $0.pointee
        }
    }
}

extension SecIdentity {
    var privateKey: SecKey? {
        var privateKey: SecKey?
        let status = SecIdentityCopyPrivateKey(self, &privateKey)
        LOG.warning("Identity \(self) doesn't contain private key. Error: \(status)")
        return privateKey
    }

    var certificate: SecCertificate? {
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(self, &certificate)
        LOG.warning("Identity \(self) doesn't contain certificate. Error: \(status)")
        return certificate
    }
}

struct OSError: Error {
    let status: OSStatus
}

func SecPKCS12Import(_ pkcs12_data: Data, _ options: CFDictionary) throws ->  [AnyObject] {
    var items: CFArray?
    let importError = SecPKCS12Import(pkcs12_data as CFData, options, &items)

    if importError == errSecSuccess {
        return items as [AnyObject]? ?? []
    } else {
        throw OSError(status: importError)
    }
}

final class DiscoveryLogViewerConnector {
    private static let decoder = JSONDecoder()

    private let logViewer: DiscoveryHandshake.LogViewer
    private let identityProvider: IdentityProvider

    init(logViewer: DiscoveryHandshake.LogViewer, identityProvider: IdentityProvider) {
        self.logViewer = logViewer
        self.identityProvider = identityProvider
    }

    func connect(service: NetService, lastLogItemId: @escaping (DiscoveryHandshake.Application) -> LastLogItemId) -> Single<LoggerConnection> {
        return async {
            let resolvedService = try await(service.resolved(withTimeout: 30))

            let okData = try await(resolvedService.txtData(containsKey: "OK", timeout: 10))

            let txt = try DiscoveryLogViewerConnector.decoder.decode(LoggerTXT.self, from: okData)

            var inputStream: InputStream?
            var outputStream: OutputStream?

            precondition(resolvedService.getInputStream(&inputStream, outputStream: &outputStream), "Couldn't get streams!")

            let stream = TwoWayStream(input: inputStream!, output: outputStream!)

            guard let identity = self.identityProvider.identity(forId: txt.identifier) else {
                fatalError("...")
            }

            let sslSettings = [
                kCFStreamSSLIsServer: true,
                kCFStreamSSLCertificates: [identity],
                kCFStreamSSLValidatesCertificateChain: false,
            ] as CFDictionary
            do {
                stream.input.setProperty(StreamSocketSecurityLevel.tlSv1, forKey: Stream.PropertyKey.socketSecurityLevelKey)

                let success = CFReadStreamSetProperty(
                    stream.input,
                    CFStreamPropertyKey(kCFStreamPropertySSLSettings),
                    sslSettings)
                assert(success)
            }

            do {
                stream.output.setProperty(StreamSocketSecurityLevel.tlSv1, forKey: Stream.PropertyKey.socketSecurityLevelKey)

                let success = CFWriteStreamSetProperty(
                    stream.output,
                    CFStreamPropertyKey(kCFStreamPropertySSLSettings),
                    sslSettings)
                assert(success)
            }

            try await(stream.open())

            let application = try DiscoveryHandshake(stream: stream).perform(for: self.logViewer)

            try stream.output.write(encodable: lastLogItemId(application))

            return LoggerConnection(service: resolvedService, stream: stream, application: application)
        }
    }

}
