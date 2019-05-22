//
//  DiscoveryHandshake.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public enum CommunicationProtocol: UInt8, Codable {
    case standard = 0
    case noSSL = 1
}

public final class DiscoveryHandshake {
    public struct LogReceiver: Codable, Equatable {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }
    public struct ApplicationRun: Codable, Equatable {
        public struct Device: Codable, Equatable {
            public enum OperatingSystem: String, Codable {
                case iOS
                case macOS
                case android
                case unknown

                public init(rawOrUnknown: String) {
                    if let value = OperatingSystem(rawValue: rawOrUnknown) {
                        self = value
                    } else {
                        self = .unknown
                    }
                }
            }
            public let id: String
            public let name: String
            public let operatingSystem: OperatingSystem
            public let systemVersion: String

            public init(id: String, name: String, operatingSystem: OperatingSystem, systemVersion: String) {
                self.id = id
                self.name = name
                self.operatingSystem = operatingSystem
                self.systemVersion = systemVersion
            }
        }
        public struct Application: Codable, Equatable {
            public let name: String
            public let identifier: String

            public init(name: String, identifier: String) {
                self.name = name
                self.identifier = identifier
            }
        }

        public let id: String
        public let date: Date
        public let applicationVersion: String
        public let seedIdentifier: String
        public let application: Application
        public let device: Device

        public init(id: String, date: Date, applicationVersion: String, seedIdentifier: String, application: Application, device: Device) {
            self.id = id
            self.date = date
            self.applicationVersion = applicationVersion
            self.seedIdentifier = seedIdentifier
            self.application = application
            self.device = device
        }
    }

    private let stream: TwoWayStream

    init(stream: TwoWayStream) {
        self.stream = stream
    }

    func perform(for viewer: LogReceiver) throws -> ApplicationRun {
        LOG.info("Sending logger info:", viewer)
        try stream.output.write(encodable: viewer)
        LOG.info("Sent logger info.")
        
        LOG.info("Receiving app info.")
        let applicationRun = try stream.input.readDecodable(ApplicationRun.self)
        LOG.info("Receiving app info:", applicationRun)

        return applicationRun
    }


    func perform(for applicationRun: ApplicationRun) throws -> LogReceiver {
        LOG.info("Receiving logger info.")
        let logViewer = try stream.input.readDecodable(LogReceiver.self)
        LOG.info("Receiving logger info:", logViewer)

        LOG.info("Sending app info:", applicationRun)
        try stream.output.write(encodable: applicationRun)
        LOG.info("Sent app info.")

        return logViewer
    }
}
