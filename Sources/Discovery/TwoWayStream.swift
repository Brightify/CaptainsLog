//
//  TwoWayStream.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public final class TwoWayStream: NSObject, StreamDelegate {
    public let input: InputStream
    public let output: OutputStream

    enum OpenError: Error {
        case cantOpenInput(Error?)
        case cantOpenOutput(Error?)
    }

    public var hasBytesAvailable: Bool {
        return input.hasBytesAvailable
    }

    public var hasSpaceAvailable: Bool {
        return output.hasSpaceAvailable
    }

//    public let hasBytesAvailable: Observable<Bool>
//    public let hasSpaceAvailable: Observable<Bool>

    private let disposeBag = DisposeBag()

    init(input: InputStream, output: OutputStream) {
        self.input = input
        self.output = output

//        hasBytesAvailable = inputDelegate.event
//            .map { event in
//                switch event {
//                case Stream.Event.hasBytesAvailable:
//                    return true
//                default:
//                    return false
//                }
//            }
//            .distinctUntilChanged()
//            .share(replay: 1, scope: .forever)
//
//        hasSpaceAvailable = outputDelegate.event
//            .map { event in
//                switch event {
//                case .hasSpaceAvailable:
//                    return true
//                default:
//                    return false
//                }
//            }
//            .distinctUntilChanged()
//            .share(replay: 1, scope: .forever)
//
//        // This assures we have the latest value available on the observable
//        hasBytesAvailable.subscribe().disposed(by: disposeBag)
//        hasSpaceAvailable.subscribe().disposed(by: disposeBag)
    }

    public func open(schedulingIn runLoop: RunLoop = .main, forMode runLoopMode: RunLoop.Mode = .default) -> Promise<Void> {
        return async {
            self.input.delegate = self
            self.input.schedule(in: runLoop, forMode: runLoopMode)
            self.input.open()
            // Wait for input stream to open
            let inputStatus = try await(self.input.status(isOneOf: .open, .error)) ?? .error
            if inputStatus == .error {
                throw OpenError.cantOpenInput(self.input.streamError)
            }

            self.output.delegate = self
            self.output.schedule(in: runLoop, forMode: runLoopMode)
            self.output.open()
            // Wait for output stream to open
            let outputStatus = try await(self.output.status(isOneOf: .open, .error)) ?? .error
            if outputStatus == .error {
                throw OpenError.cantOpenOutput(self.output.streamError)
            }
        }
    }

    public func close() {
        input.close()
        output.close()
    }

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        LOG.verbose(#function, aStream, eventCode)
//        eventSubject.onNext(eventCode)
    }

    deinit {
        close()

        // We need to remove the delegate, otherwise it could get called later when it's deallocated.
        input.delegate = nil
        output.delegate = nil
    }
}

extension Stream.Event: CustomStringConvertible {
    public var description: String {
        switch self {
        case .openCompleted:
            return "Stream.Event.openCompleted"
        case .hasBytesAvailable:
            return "Stream.Event.hasBytesAvailable"
        case .hasSpaceAvailable:
            return "Stream.Event.hasSpaceAvailable"
        case .errorOccurred:
            return "Stream.Event.errorOccurred"
        case .endEncountered:
            return "Stream.Event.endEncountered"
        default:
            return "Stream.Event(rawValue: \(rawValue))"
        }
    }
}
