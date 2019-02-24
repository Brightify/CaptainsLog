//
//  Stream+Rx.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public extension Stream {
//    func observeStatus(observer: Observer) -> Disposable {
//        return Observable<Int>.interval(0.1, scheduler: MainScheduler.instance)
//            .map { _ in self.streamStatus }
//            .startWith(streamStatus)
//            .distinctUntilChanged()
//    }

    func status(isOneOf acceptedStates: Status...) -> Promise<Status> {
        return Promises.blockUntil {
            acceptedStates.contains(self.streamStatus)
        }.map { self.streamStatus }
    }
}
