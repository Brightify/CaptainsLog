//
//  NetService+loggerService.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation
import RxSwift

extension NetService {
    static func loggerService(
        named name: String,
        domain: String = Constants.domain,
        type: String = Constants.type,
        port: Int32 = Constants.port) -> NetService {

        return NetService(domain: domain, type: type, name: name, port: port)
    }
}

extension NetService {
    private class AcceptDelegate: NSObject, NetServiceDelegate {
        private let didAcceptConnection: (TwoWayStream) -> Void

        init(didAcceptConnection: @escaping (TwoWayStream) -> Void) {
            self.didAcceptConnection = didAcceptConnection
        }

        func netService(_ sender: NetService, didAcceptConnectionWith inputStream: InputStream, outputStream: OutputStream) {
            didAcceptConnection(TwoWayStream(input: inputStream, output: outputStream))
        }
    }

    func publish() -> Observable<TwoWayStream> {
        return Observable.create { observer in
            let delegate = AcceptDelegate(didAcceptConnection: observer.onNext)
            self.delegate = delegate

            self.schedule(in: .current, forMode: .default)
            self.publish(options: .listenForConnections)

            return Disposables.create {
                withExtendedLifetime(delegate) { }
                self.delegate = nil
                self.stop()
            }
        }
    }
}
