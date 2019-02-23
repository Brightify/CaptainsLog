//
//  LogViewerConnection.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public final class LogViewerConnection {
    public let service: NetService
    public let stream: TwoWayStream
    public let logViewer: DiscoveryHandshake.LogReceiver
    public let lastReceivedItemId: LastLogItemId

    init(service: NetService, stream: TwoWayStream, logViewer: DiscoveryHandshake.LogReceiver, lastReceivedItemId: LastLogItemId) {
        self.service = service
        self.stream = stream
        self.logViewer = logViewer
        self.lastReceivedItemId = lastReceivedItemId
    }

    func close() {
        LOG.info("Closing connection for log receiver service:", service)
        service.stop()
        stream.input.close()
        stream.output.close()
    }
}
