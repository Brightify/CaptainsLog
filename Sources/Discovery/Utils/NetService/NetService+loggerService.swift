//
//  NetService+loggerService.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

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
        let txtRecordSet = service.setTXTRecord(txtRecordData)
        assert(txtRecordSet, "Couldn't set TXT record")
        return service
    }
}
