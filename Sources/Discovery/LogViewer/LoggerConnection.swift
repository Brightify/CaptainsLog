//
//  LoggerConnection.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public final class LoggerConnection {
    public let service: NetService
    public let applicationRun: DiscoveryHandshake.ApplicationRun

    public private(set) var stream: TwoWayStream

    init(service: NetService, stream: TwoWayStream, applicationRun: DiscoveryHandshake.ApplicationRun) {
        self.service = service
        self.stream = stream
        self.applicationRun = applicationRun
    }

    func close() {
        LOG.info("Closing connection for logger service:", service)
        service.stop()
        stream.input.close()
        stream.output.close()
    }
}
