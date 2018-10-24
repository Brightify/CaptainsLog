//
//  DiscoveryHandshake.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation
// TODO Handshake should encorporate encryption and signature verification
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
        print("INFO: Sending logger info:", viewer)
        try stream.output.write(encodable: viewer)
        print("INFO: Sent logger info.")

        print("INFO: Receiving app info.")
        let application = try stream.input.readDecodable(Application.self)
        print("INFO: Receiving app info:", application)

        return application
    }


    func perform(for application: Application) throws -> LogViewer {
        print("INFO: Receiving logger info.")
        let logViewer = try stream.input.readDecodable(LogViewer.self)
        print("INFO: Receiving logger info:", logViewer)

        print("INFO: Sending app info:", application)
        try stream.output.write(encodable: application)
        print("INFO: Sent app info.")

        return logViewer
    }
}
