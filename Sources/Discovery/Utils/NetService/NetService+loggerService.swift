//
//  NetService+loggerService.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation
import RxSwift

struct LoggerTXT: Codable {
    let identifier: String
}

extension NetService {
    private static let encoder = JSONEncoder()

    static func loggerService(
        named name: String,
        identifier: String,
        domain: String,
        type: String,
        port: Int) -> NetService {

        let txt = LoggerTXT(identifier: identifier)
        let txtData = try! encoder.encode(txt)
        let txtRecordData = NetService.data(fromTXTRecord: ["OK": txtData])

        let service = NetService(domain: domain, type: type, name: name, port: Int32(port))
        assert(service.setTXTRecord(txtRecordData), "Couldn't set TXT record")
        return service
    }
}

extension NetService {
    private class AcceptDelegate: NSObject, NetServiceDelegate {
        private let didAcceptConnection: (TwoWayStream) -> Void

        init(didAcceptConnection: @escaping (TwoWayStream) -> Void) {
            self.didAcceptConnection = didAcceptConnection
        }

        func netService(_ sender: NetService, didAcceptConnectionWith inputStream: InputStream, outputStream: OutputStream) {
            print(#function, sender)
            didAcceptConnection(TwoWayStream(input: inputStream, output: outputStream))
        }

        func netServiceWillPublish(_ sender: NetService) {
            print(#function, sender)
        }

        func netServiceDidPublish(_ sender: NetService) {
            print(#function, sender)
            sender.setTXTRecord(sender.txtRecordData())
        }

        func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
            print(#function, sender, errorDict)
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
