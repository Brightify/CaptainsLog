//
//  InputStream+Helpers.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public extension InputStream {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()

    func readBytes(length: Int) throws -> [UInt8] {
        var totalBytes = Array<UInt8>(repeating: 0, count: length)
        let bytesPointer = UnsafeMutablePointer(&totalBytes)
        var readBytes = 0

        repeat {
            let buffer = bytesPointer.advanced(by: readBytes)
            let readLength = read(buffer, maxLength: length - readBytes)
            guard readLength > 0 else {
                if let streamError = streamError {
                    throw streamError
                } else {
                    throw StreamDisconnectedError()
                }
            }

            readBytes += readLength
        } while readBytes < length

        return totalBytes
    }

    func readData() throws -> Data {
        let length = try readRaw(Int.self)
        let dataBytes = try readBytes(length: length)

        return Data(bytes: dataBytes)
    }

    func readDecodable<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        let data = try readData()
        return try InputStream.decoder.decode(T.self, from: data)
    }

    private func readRaw<T>(_ type: T.Type = T.self) throws -> T {
        let bytes = try readBytes(length: MemoryLayout<T>.size)
        return fromByteArray(bytes.reversed())
    }

    private func fromByteArray<T>(_ value: [UInt8], _: T.Type = T.self) -> T {
        return value.withUnsafeBytes {
            $0.baseAddress!.load(as: T.self)
        }
    }
}
