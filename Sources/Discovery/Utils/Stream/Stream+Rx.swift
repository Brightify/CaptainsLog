//
//  Stream+Rx.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation
import RxSwift

public extension Stream {
    func observeStatus() -> Observable<Status> {
        return Observable<Int>.timer(0.1, scheduler: MainScheduler.instance)
            .map { _ in self.streamStatus }
            .startWith(streamStatus)
            .distinctUntilChanged()
    }

    func status(isOneOf acceptedStates: Status...) -> Maybe<Status> {
        let acceptedStateSet = Set(acceptedStates)
        return observeStatus()
            .filter(acceptedStateSet.contains)
            .take(1)
            .asMaybe()
    }
}
