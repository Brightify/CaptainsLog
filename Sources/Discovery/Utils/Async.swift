//
//  Async.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 27/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

import RxSwift

public struct Queue {
    public static var async = DispatchQueue(label: "org.brightify.CaptainsLog.async-queue", attributes: .concurrent)
    public static let await = DispatchQueue(label: "org.brightify.CaptainsLog.await-queue", attributes: .concurrent)
    public static let work = DispatchQueue(label: "org.brightify.CaptainsLog.work-queue", attributes: .concurrent)
}

public struct AwaitTimeoutError: Error { }

public final class Promise<T> {
    public typealias Resolve = (T) -> Void
    public typealias Reject = (Error) -> Void
    public typealias Work = (_ resolve: @escaping Resolve, _ reject: @escaping Reject) -> Void

    public enum Result {
        case success(T)
        case error(Error)
    }
    public final class Catchable {
        private let promise: Promise

        init(promise: Promise) {
            self.promise = promise
        }

        func catchError(_ handler: @escaping (Error) -> Void) {
            promise.catchError(handler)
        }
    }

    private let lock = DispatchQueue(label: "org.brightify.CaptainsLog.promise-lock-queue")

    private var observers: [(Result) -> Void] = []
    private var result: Result?

    private let queue: DispatchQueue
    private let work: Work

    public init(queue: DispatchQueue = Queue.work, work: @escaping Work) {
        self.queue = queue
        self.work = work

        queue.async {
            work(self.resolve, self.reject)
        }
    }

    public func observeResult(_ callback: @escaping (Result) -> Void) {
        lock.sync {
            observers.append(callback)

            if let result = result {
                callback(result)
            }
        }
    }

    public func then<NEXT>(on otherQueue: DispatchQueue? = nil, do work: @escaping (T) -> Promise<NEXT>) -> Promise<NEXT> {
        let promise = Promise<NEXT>.pending()

        observeResult { result in
            switch result {
            case .success(let value):
                (otherQueue ?? self.queue).async {
                    let workPromise = work(value)
                    workPromise.observeResult(promise.fullfill)
                }
            case .error(let error):
                promise.reject(error)
            }
        }

        return promise
    }

    @discardableResult
    public func done(_ work: @escaping (T) -> Void) -> Catchable {
        observeResult { result in
            switch result {
            case .success(let value):
                work(value)
            case .error:
                break
            }
        }

        return Catchable(promise: self)
    }

    public func catchError(_ handler: @escaping (Error) -> Void) {
        observeResult { result in
            switch result {
            case .success:
                break
            case .error(let error):
                handler(error)
            }
        }
    }

    @discardableResult
    public func ensure(cleanup: @escaping () -> Void) -> Promise {
        observeResult { _ in
            cleanup()
        }

        return self
    }

    public func resolve(_ value: T) {
        fullfill(result: .success(value))
    }

    public func reject(_ error: Error) {
        fullfill(result: .error(error))
    }

    public func fullfill(result: Result) {
        lock.sync {
            guard self.result == nil else {
                fatalError("Promise canot be resolved more than once!")
            }

            self.result = result

            for observer in observers {
                observer(result)
            }
        }
    }

    public func debug(_ label: String) {
        observeResult { result in
            switch result {
            case .success(let value):
                print("\(label): Promise resolved:", value)
            case .error(let error):
                print("\(label): Promise rejected:", error)
            }
        }
    }

    public static func pending(queue: DispatchQueue = Queue.work) -> Promise<T> {
        return Promise(queue: queue, work: { _, _ in })
    }
}

public func await<T>(timeout: DispatchTime = .distantFuture, _ maybe: Maybe<T>) throws -> T? {
    do {
        return try await(timeout: timeout, maybe.asObservable().asSingle())
    } catch RxError.noElements {
        return nil
    } catch {
        throw error
    }
}

public func await<T>(timeout: DispatchTime = .distantFuture, _ single: Single<T>) throws -> T {
    var event: SingleEvent<T>?
    
    let semaphore = DispatchSemaphore(value: 0)

    let subscription = single
        .subscribeOn(ConcurrentDispatchQueueScheduler(queue: Queue.await))
        .observeOn(ConcurrentDispatchQueueScheduler(queue: Queue.await))
        .subscribe { e in
            dispatchPrecondition(condition: .onQueue(Queue.await))

            event = e

            semaphore.signal()
        }
    defer { subscription.dispose() }

    let waitingResult = semaphore.wait(timeout: timeout)

    switch (waitingResult, event) {
    case (.success, .success(let value)?):
        return value

    case (.success, .error(let error)?):
        throw error

    case (.success, nil):
        fatalError("Something signalled the semaphore without providing a result!")

    case (.timedOut, _):
        throw AwaitTimeoutError()
    }
}

public func await<T>(timeout: DispatchTime = .distantFuture, _ body: @escaping () throws -> T) throws -> T {
    let single = Single<T>.create { resolve in
        dispatchPrecondition(condition: .onQueue(Queue.await))

        do {
            resolve(.success(try body()))
        } catch {
            resolve(.error(error))
        }

        return Disposables.create()
    }

    return try await(timeout: timeout, single)
}

@discardableResult
public func async<T>(on queue: DispatchQueue = Queue.async, _ body: @escaping () throws -> T) -> Single<T> {
    return Single<T>.create { resolved in
        dispatchPrecondition(condition: .onQueue(queue))

        do {
            let value = try body()
            resolved(.success(value))
        } catch {
            resolved(.error(error))
        }

        return Disposables.create()
    }.subscribeOn(ConcurrentDispatchQueueScheduler(queue: queue))
}
