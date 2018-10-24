//
//  TwoWayStream.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation
import RxSwift

public struct TwoWayStream {
    public let input: InputStream
    public let output: OutputStream

    enum OpenError: Error {
        case cantOpenInput(Error?)
        case cantOpenOutput(Error?)
    }

    public func open(schedulingIn runLoop: RunLoop = .current, forMode runLoopMode: RunLoop.Mode = .default) -> Single<Void> {
        return async {
            self.input.setProperty(StreamSocketSecurityLevel.tlSv1, forKey: Stream.PropertyKey.socketSecurityLevelKey)

            CFReadStreamSetProperty(
                self.input,
                CFStreamPropertyKey(kCFStreamPropertySSLSettings),
                [kCFStreamSSLIsServer: true] as CFDictionary)
            self.input.schedule(in: runLoop, forMode: runLoopMode)
            self.input.open()
            // Wait for input stream to open
            let inputStatus = try await(self.input.status(isOneOf: .open, .error)) ?? .error
            if inputStatus == .error {
                throw OpenError.cantOpenInput(self.input.streamError)
            }

            self.output.setProperty(StreamSocketSecurityLevel.tlSv1, forKey: Stream.PropertyKey.socketSecurityLevelKey)
            self.output.schedule(in: runLoop, forMode: runLoopMode)
            self.output.open()
            // Wait for output stream to open
            let outputStatus = try await(self.output.status(isOneOf: .open, .error)) ?? .error
            if outputStatus == .error {
                throw OpenError.cantOpenOutput(self.output.streamError)
            }
        }
    }
}
