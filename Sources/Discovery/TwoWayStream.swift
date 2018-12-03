//
//  TwoWayStream.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation
import RxSwift

public final class TwoWayStream {
    private let inputDelegate = DefaultStreamDelegate()
    private let outputDelegate = DefaultStreamDelegate()

    public let input: InputStream
    public let output: OutputStream

    enum OpenError: Error {
        case cantOpenInput(Error?)
        case cantOpenOutput(Error?)
    }

    public let hasBytesAvailable: Observable<Bool>
    public let hasSpaceAvailable: Observable<Bool>

    private let disposeBag = DisposeBag()

    init(input: InputStream, output: OutputStream) {
        self.input = input
        self.output = output

        hasBytesAvailable = inputDelegate.event
            .map { event in
                switch event {
                case Stream.Event.hasBytesAvailable:
                    return true
                default:
                    return false
                }
            }
            .distinctUntilChanged()
            .share(replay: 1, scope: .forever)

        hasSpaceAvailable = outputDelegate.event
            .map { event in
                switch event {
                case .hasSpaceAvailable:
                    return true
                default:
                    return false
                }
            }
            .distinctUntilChanged()
            .share(replay: 1, scope: .forever)

        // This assures we have the latest value available on the observable
        hasBytesAvailable.subscribe().disposed(by: disposeBag)
        hasSpaceAvailable.subscribe().disposed(by: disposeBag)
    }

    public func open(schedulingIn runLoop: RunLoop = .main, forMode runLoopMode: RunLoop.Mode = .default) -> Single<Void> {
        return async {
            self.input.delegate = self.inputDelegate
            self.input.schedule(in: runLoop, forMode: runLoopMode)
            self.input.open()
            // Wait for input stream to open
            let inputStatus = try await(self.input.status(isOneOf: .open, .error).debug("wtf is this")) ?? .error
            if inputStatus == .error {
                throw OpenError.cantOpenInput(self.input.streamError)
            }

            self.output.delegate = self.outputDelegate
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
        self.input.close()
        self.output.close()
    }
}

private extension TwoWayStream {
    final class DefaultStreamDelegate: NSObject, StreamDelegate {
        private let eventSubject = PublishSubject<Stream.Event>()
        var event: Observable<Stream.Event> {
            return eventSubject
        }

        func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
            LOG.verbose(#function, aStream, eventCode)
            eventSubject.onNext(eventCode)
        }
    }

}
