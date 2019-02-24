//
//  Async.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 27/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

public struct Queue {
    public static let async = DispatchQueue(label: "org.brightify.CaptainsLog.async-queue", attributes: .concurrent)
    public static let await = DispatchQueue(label: "org.brightify.CaptainsLog.await-queue", attributes: .concurrent)
    public static let work = DispatchQueue(label: "org.brightify.CaptainsLog.work-queue", attributes: .concurrent)
    public static let timer = DispatchQueue(label: "org.brightify.CaptainsLog.timer-queue", attributes: .concurrent)
}

public final class Async {
    static func runTimer(queue: DispatchQueue = Queue.timer, work: @escaping () -> DispatchTimeInterval?) -> Disposable {
        let disposable = Disposables.create()

        func recursiveTimer() {
            guard !disposable.isDisposed, let requestedDelay = work() else { return }
            queue.asyncAfter(deadline: DispatchTime.now() + requestedDelay) {
                if disposable.isDisposed { return }
                runTimer(queue: queue, work: work)
            }
        }

        queue.async {
            recursiveTimer()
        }

        return disposable
    }
}

public final class ObserverBag<T> {
    typealias Observer = (T) -> Void

    private var counter = Int.min
    private var observers: [Int: Observer] = [:]

    private let registrationLock = DispatchQueue(label: "org.brightify.CaptainsLog.observer-bag-registration-lock")

    public init() {

    }

    func register(observer: @escaping Observer) -> Disposable {
        let observerId: Int = registrationLock.sync {
            let observerId = counter
            observers[observerId] = observer
            counter += 1
            return observerId
        }

        return Disposables.create {
            self.unregister(observerId: observerId)
        }
    }

    private func unregister(observerId: Int) {
        registrationLock.sync {
            observers[observerId] = nil
        }
    }

    public func notifyObservers(value: T) {
        let observersCopy = observers.values
        observersCopy.forEach {
            $0(value)
        }
    }

    public func dispose() {
        registrationLock.sync {
            observers.removeAll()
        }
    }
}

extension Disposable {
    func disposed(by bag: DisposeBag) {
        bag.add(self)
    }
}

public class DisposeBag {
    private var disposables: [Disposable] = []

    func add(_ disposable: Disposable) {
        disposables.append(disposable)
    }

    deinit {
        disposables.forEach { $0.dispose() }
    }
}

public protocol Disposable {
    var isDisposed: Bool { get }

    func dispose()
}

enum Disposables {
    private class DefaultDisposable: Disposable {
        private let doDispose: () -> Void

        private(set) var isDisposed: Bool = false

        init(doDispose: @escaping () -> Void) {
            self.doDispose = doDispose
        }

        func dispose() {
            defer { isDisposed = true }
            doDispose()
        }
    }

    static func create(_ doDispose: @escaping () -> Void = { }) -> Disposable {
        return DefaultDisposable(doDispose: doDispose)
    }
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

    public func map<NEXT>(transform: @escaping (T) throws -> NEXT) -> Promise<NEXT> {
        return then { try Promise<NEXT>.just(transform($0)) }
    }

    public func then<NEXT>(on otherQueue: DispatchQueue? = nil, do work: @escaping (T) throws -> Promise<NEXT>) -> Promise<NEXT> {
        let promise = Promise<NEXT>.pending()

        observeResult { result in
            switch result {
            case .success(let value):
                (otherQueue ?? self.queue).async {
                    do {
                        let workPromise = try work(value)
                        workPromise.observeResult(promise.fulfill)
                    } catch {
                        promise.reject(error)
                    }
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
    public func finally(cleanup: @escaping () -> Void) -> Promise {
        observeResult { _ in
            cleanup()
        }

        return self
    }

    public func resolve(_ value: T) {
        fulfill(result: .success(value))
    }

    public func reject(_ error: Error) {
        fulfill(result: .error(error))
    }

    public func fulfill(result: Result) {
        lock.sync {
            guard self.result == nil else {
                fatalError("Promise can't be resolved more than once!")
            }

            self.result = result

            for observer in observers {
                observer(result)
            }
        }
    }

    public func debug(_ label: String) -> Promise {
        observeResult { result in
            switch result {
            case .success(let value):
                LOG.debug("\(label): Promise resolved:", value)
            case .error(let error):
                LOG.debug("\(label): Promise rejected:", error)
            }
        }

        return self
    }

    public static func pending(queue: DispatchQueue = Queue.work) -> Promise<T> {
        return Promise(queue: queue, work: { _, _ in })
    }

    public static func just(_ value: T) -> Promise<T> {
        return Promise(work: { resolve, _ in resolve(value) })
    }

    public static func error(_ error: Error) -> Promise<T> {
        return Promise(work: { _, reject in reject(error) })
    }

}

public enum Promises {
    public static func blockUntil(queue: DispatchQueue = Queue.work, delay: DispatchTimeInterval = .milliseconds(50), condition: @escaping () -> Bool) -> Promise<Void> {
        return Promise(queue: queue) { resolve, reject in
            Async.runTimer(queue: queue) {
                if condition() {
                    resolve(())
                    return nil
                } else {
                    return delay
                }
            }
        }
    }
}

public func await<T>(timeout: DispatchTime = .distantFuture, _ promise: Promise<T>) throws -> T {
    var promiseResult: Promise<T>.Result?

    let semaphore = DispatchSemaphore(value: 0)

    promise.observeResult { result in
        promiseResult = result

        semaphore.signal()
    }

    let waitingResult = semaphore.wait(timeout: timeout)

    switch (waitingResult, promiseResult) {
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
    let promise = Promise<T>() { resolve, reject in
        do {
            resolve(try body())
        } catch {
            reject(error)
        }
    }

    return try await(timeout: timeout, promise)
}

@discardableResult
public func async<T>(on queue: DispatchQueue = Queue.async, _ body: @escaping () throws -> T) -> Promise<T> {
//    LOG.verbose("Async will start")
    return Promise<T>(queue: queue) { resolved, errored in
        do {
//            LOG.verbose("Async did start")
            let value = try body()
//            LOG.verbose("Async will resolve: \(value)")
            resolved(value)
//            LOG.verbose("Async did resolve: \(value)")
        } catch {
//            LOG.verbose("Async will fail: \(error)")
            errored(error)
//            LOG.verbose("Async did fail: \(error)")
        }
    }.finally {
//        LOG.verbose("Async completed")
    }
}
