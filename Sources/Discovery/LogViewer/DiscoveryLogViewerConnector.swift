//
//  DiscoveryClientConnector.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation
import RxSwift

final class DiscoveryLogViewerConnector {
    private let logViewer: DiscoveryHandshake.LogViewer

    init(logViewer: DiscoveryHandshake.LogViewer) {
        self.logViewer = logViewer
    }

    func connect(service: NetService, lastLogItemId: @escaping (DiscoveryHandshake.Application) -> LastLogItemId) -> Single<LoggerConnection> {
        return async {
            let resolvedService = try await(service.resolved(withTimeout: 30))

            var inputStream: InputStream?
            var outputStream: OutputStream?

            precondition(resolvedService.getInputStream(&inputStream, outputStream: &outputStream), "Couldn't get streams!")

            let stream = TwoWayStream(input: inputStream!, output: outputStream!)

            try await(stream.open())

            let application = try DiscoveryHandshake(stream: stream).perform(for: self.logViewer)

            try stream.output.write(encodable: lastLogItemId(application))

            return LoggerConnection(service: resolvedService, stream: stream, application: application)
        }
    }
}
