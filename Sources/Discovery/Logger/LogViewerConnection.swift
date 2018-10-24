//
//  LogViewerConnection.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public final class LogViewerConnection {
    public let stream: TwoWayStream
    public let logViewer: DiscoveryHandshake.LogViewer
    public let lastReceivedItemId: LastLogItemId

    init(stream: TwoWayStream, logViewer: DiscoveryHandshake.LogViewer, lastReceivedItemId: LastLogItemId) {
        self.stream = stream
        self.logViewer = logViewer
        self.lastReceivedItemId = lastReceivedItemId
    }

    func close() {
        stream.input.close()
        stream.output.close()
    }
}
