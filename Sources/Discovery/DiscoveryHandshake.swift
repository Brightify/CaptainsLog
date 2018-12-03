//
//  DiscoveryHandshake.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public final class DiscoveryHandshake {
    public struct LogViewer: Codable, Equatable {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }
    public struct Application: Codable, Equatable {
        public let id: String
        public let name: String
        public let identifier: String
        public let version: String
        public let date: Date

        public init(id: String, name: String, identifier: String, version: String, date: Date) {
            self.id = id
            self.name = name
            self.identifier = identifier
            self.version = version
            self.date = date
        }
    }

    private let stream: TwoWayStream

    init(stream: TwoWayStream) {
        self.stream = stream
    }

    func perform(for viewer: LogViewer) throws -> Application {
        LOG.info("Sending logger info:", viewer)
        try stream.output.write(encodable: viewer)
        LOG.info("Sent logger info.")

        LOG.info("Receiving app info.")
        let application = try stream.input.readDecodable(Application.self)
        LOG.info("Receiving app info:", application)

        return application
    }


    func perform(for application: Application) throws -> LogViewer {
        LOG.info("Receiving logger info.")
        let logViewer = try stream.input.readDecodable(LogViewer.self)
        LOG.info("Receiving logger info:", logViewer)

        LOG.info("Sending app info:", application)
        try stream.output.write(encodable: application)
        LOG.info("Sent app info.")

        return logViewer
    }
}
