//
//  LoggerConnection.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public final class LoggerConnection {
    public let applicationRun: DiscoveryHandshake.ApplicationRun

    public private(set) var stream: TwoWayStream

    init(stream: TwoWayStream, applicationRun: DiscoveryHandshake.ApplicationRun) {
        self.stream = stream
        self.applicationRun = applicationRun
    }

    func close() {
        LOG.info("Closing connection for logger:", applicationRun)
        stream.input.close()
        stream.output.close()
    }
}
