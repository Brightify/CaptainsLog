//
//  RetryBehavior.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

struct RetryBehavior {
    private let nextDelay: (TimeInterval) -> TimeInterval
    private var remaining: Int
    let delay: TimeInterval

    var canRetry: Bool {
        return remaining > 0
    }

    init(retries: Int, initialDelay: TimeInterval, nextDelay: @escaping (TimeInterval) -> TimeInterval) {
        self.remaining = retries
        self.delay = initialDelay
        self.nextDelay = nextDelay
    }

    func next() -> RetryBehavior {
        return RetryBehavior(
            retries: remaining - 1,
            initialDelay: nextDelay(delay),
            nextDelay: nextDelay)
    }

    static let `default` = RetryBehavior(retries: 10, initialDelay: 0.1, nextDelay: { $0 * 2 })

    static let short = RetryBehavior(retries: 5, initialDelay: 0.1, nextDelay: { $0 * 2 })

    func retry<RESULT>(work: () throws -> RESULT) throws -> RESULT {
        do {
            return try work()
        } catch where canRetry {
            Thread.sleep(forTimeInterval: delay)

            return try next().retry(work: work)
        } catch {
            throw error
        }
    }
}
