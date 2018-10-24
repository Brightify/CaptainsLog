//
//  DiscoveryServiceBrowserDelegate.swift
//  CaptainsLog
//
//  Created by Tadeas Kriz on 10/24/18.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

protocol DiscoveryServiceBrowserDelegate: AnyObject {
    func discoveryServiceBrowser(_ browser: DiscoveryServiceBrowser, didResolveServices: [NetService])
}
