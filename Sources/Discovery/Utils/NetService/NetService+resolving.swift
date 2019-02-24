//
//  NetService+resolving.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

extension NetService {
    private final class ResolutionDelegate: NSObject, NetServiceDelegate {
        struct ResolutionError: Error {
            let info: [String: NSNumber]
        }

        let serviceResolved: (ResolutionError?) -> Void

        init(serviceResolved: @escaping (ResolutionError?) -> Void) {
            self.serviceResolved = serviceResolved
        }

        func netServiceDidResolveAddress(_ sender: NetService) {
            LOG.verbose(#function, sender)

            serviceResolved(nil)
        }

        func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
            LOG.verbose(#function, sender, errorDict)

            serviceResolved(ResolutionError(info: errorDict))
        }
    }

    func resolved(withTimeout timeout: TimeInterval) -> Promise<NetService> {
        guard addresses == nil else { return Promise.just(self) }

        return Promise { resolve, fail in
            let delegate = ResolutionDelegate(serviceResolved: { error in
                self.delegate = nil
                if let error = error {
                    fail(error)
                } else {
                    resolve(self)
                }
            })
            self.delegate = delegate

            self.resolve(withTimeout: timeout)

//            return Disposables.create {
//                withExtendedLifetime(delegate) { }
//                self.delegate = nil
//            }
        }
    }
}

extension NetService {
//    private final class TxtChangedDelegate: NSObject, NetServiceDelegate {
//        let txtRecordUpdated: (Data) -> Void
//
//        init(txtRecordUpdated: @escaping (Data) -> Void) {
//            self.txtRecordUpdated = txtRecordUpdated
//        }
//
//        func netService(_ sender: NetService, didUpdateTXTRecord data: Data) {
//            LOG.verbose(#function, sender, data)
//            txtRecordUpdated(data)
//        }
//    }
//
//    func txtData(containsKey key: String, timeout: TimeInterval = 0) -> Promise<Data> {
//        let updatedTxtRecord = Observable<Data?>.create { observer in
//            let delegate = TxtChangedDelegate(txtRecordUpdated: observer.onNext)
//            self.delegate = delegate
//
//            self.startMonitoring()
//
//            return Disposables.create {
//                withExtendedLifetime(delegate) { }
//                self.stopMonitoring()
//                self.delegate = nil
//            }
//        }
//
//        let result = updatedTxtRecord.startWith(txtRecordData())
//            .flatMap { recordData -> Observable<Data> in
//                guard
//                    let records = recordData.map(NetService.dictionary(fromTXTRecord:)),
//                    let record = records[key] else {
//                        return .empty()
//                }
//
//                return .just(record)
//            }
//            .take(1)
//            .asSingle()
//
//        if timeout > 0 {
//            return result.timeout(timeout, scheduler: MainScheduler.instance)
//        } else {
//            return result
//        }
//    }
}
