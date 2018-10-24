//
//  LogReceiver.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation
import RxSwift

public final class LogReceiver {
    public let itemReceived: Observable<LogItem>

    let connection: LoggerConnection

    public init(connection: LoggerConnection) {
        self.connection = connection

        var remainingRetries = 10
        var lastRetryDelay = 0.2

        func readLogItem() -> Observable<LogItem> {
            return Observable
                .deferred {
                    let item = try connection.stream.input.readDecodable(LogItem.self)

                    return Observable.concat(Observable.just(item), readLogItem())
            }
        }

        itemReceived = readLogItem()
    }
}
