//
//  NetService+resolving.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation
import RxSwift

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
            print(#function, sender)

            serviceResolved(nil)
        }

        func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
            print(#function, sender, errorDict)

            serviceResolved(ResolutionError(info: errorDict))
        }
    }

    func resolved(withTimeout timeout: TimeInterval) -> Single<NetService> {
        guard addresses == nil else { return .just(self) }

        return Single.create { fullfill in
            let delegate = ResolutionDelegate(serviceResolved: { error in
                if let error = error {
                    fullfill(.error(error))
                } else {
                    fullfill(.success(self))
                }
            })
            self.delegate = delegate

            self.resolve(withTimeout: timeout)

            return Disposables.create {
                withExtendedLifetime(delegate) { }
                self.delegate = nil
            }
        }
    }

}
