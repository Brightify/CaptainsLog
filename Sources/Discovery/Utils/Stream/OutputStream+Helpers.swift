//
//  OutputStream+Helpers.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public extension OutputStream {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    func write(bytes: [UInt8]) throws {
        let totalBytes = bytes.count
        let bytesPointer = UnsafePointer(bytes)
        var totalWrittenBytes = 0

        repeat {
            let buffer = bytesPointer.advanced(by: totalWrittenBytes)
            let writtenBytes = write(buffer, maxLength: totalBytes - totalWrittenBytes)

            guard writtenBytes > 0 else {
                if let streamError = streamError {
                    throw streamError
                } else {
                    throw StreamDisconnectedError()
                }
            }

            totalWrittenBytes += writtenBytes

        } while totalWrittenBytes < totalBytes
    }

    func write(data: Data) throws {
        let bytes = Array(data)
        try write(raw: Int64(bytes.count))
        try write(bytes: bytes)
    }

    func write<T: Encodable>(encodable value: T) throws {
        let data = try OutputStream.encoder.encode(value)
        try write(data: data)
    }

    private func write<T>(raw value: T) throws {
        let bytes = toByteArray(value)
        try write(bytes: bytes)
    }
    
    private func toByteArray<T>(_ value: T) -> [UInt8] {
        var value = value
        return withUnsafeBytes(of: &value) { Array($0).reversed() }
    }
}
