//
//  CaptainsLogHTTPProtocol.swift
//  CaptainsLog-macOS
//
//  Created by Robin Krenecky on 24/10/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import Foundation

final class CaptainsLogHTTPProtocol: URLProtocol {
    struct Constants {
        static let RequestHandledKey = "URLProtocolRequestHandled"
    }

    private static var isActivated = false

    private var session: URLSession?
    private var sessionTask: URLSessionDataTask?
    private var currentRequest: Request?

    private var responseBody: Data?
    private var response: Request.Response?

    override init(request: URLRequest, cachedResponse: CachedURLResponse?, client: URLProtocolClient?) {
        super.init(request: request, cachedResponse: cachedResponse, client: client)

        if session == nil {
            session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        }
    }

    static func activate() {
        swizzleDefaultSessionConfiguration()
        CaptainsLogHTTPProtocol.isActivated = true
    }

    static func deactivate() {
        CaptainsLogHTTPProtocol.isActivated = false
    }

    override class func canInit(with request: URLRequest) -> Bool {
        if CaptainsLogHTTPProtocol.property(forKey: Constants.RequestHandledKey, in: request) != nil || !isActivated {
            return false
        }

        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        let newRequest = ((request as NSURLRequest).mutableCopy() as? NSMutableURLRequest)!
        CaptainsLogHTTPProtocol.setProperty(true, forKey: Constants.RequestHandledKey, in: newRequest)
        sessionTask = session?.dataTask(with: newRequest as URLRequest)
        sessionTask?.resume()
    }

    override func stopLoading() {
        sessionTask?.cancel()

        guard
            let method = HTTPMethod(rawValue: request.httpMethod ?? ""),
            let url = request.url,
            let headers = request.allHTTPHeaderFields,
            let response = response else {
                return
        }

        currentRequest = Request(method: method,
                                 url: url,
                                 headers: headers,
                                 time: Date(),
                                 body: body(from: request),
                                 response: response)

        CaptainsLogHTTPRequestWatcher.instance.log?.log(item: LogItem(id: UUID().uuidString, kind: .request(currentRequest!)))
    }

    private func body(from request: URLRequest) -> Data? {
        return request.httpBody ?? request.httpBodyStream.flatMap { stream in
            let data = NSMutableData()
            stream.open()
            while stream.hasBytesAvailable {
                var buffer = [UInt8](repeating: 0, count: 1024)
                let length = stream.read(&buffer, maxLength: buffer.count)
                data.append(buffer, length: length)
            }
            stream.close()
            return data as Data
        }
    }

    private static func swizzleDefaultSessionConfiguration() {
        let defaultSessionConfiguration = class_getClassMethod(URLSessionConfiguration.self, #selector(getter: URLSessionConfiguration.default))
        let captainsLogDefaultSessionConfiguration = class_getClassMethod(URLSessionConfiguration.self, #selector(URLSessionConfiguration.captainsLogDefaultSessionConfiguration))
        method_exchangeImplementations(defaultSessionConfiguration!, captainsLogDefaultSessionConfiguration!)

        let ephemeralSessionConfiguration = class_getClassMethod(URLSessionConfiguration.self, #selector(getter: URLSessionConfiguration.ephemeral))
        let captainsLogEphemeralSessionConfiguration = class_getClassMethod(URLSessionConfiguration.self, #selector(URLSessionConfiguration.captainsLogEphemeralSessionConfiguration))
        method_exchangeImplementations(ephemeralSessionConfiguration!, captainsLogEphemeralSessionConfiguration!)
    }
}

extension CaptainsLogHTTPProtocol: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        client?.urlProtocol(self, didLoad: data)
        if response?.body == nil {
            response?.body = data
        } else {
            response?.body?.append(data)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let policy = URLCache.StoragePolicy(rawValue: request.cachePolicy.rawValue) ?? .notAllowed
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: policy)
        completionHandler(.allow)

        guard let response = response as? HTTPURLResponse, let headers = response.allHeaderFields as? [String: String] else { return }

        self.response = Request.Response(time: Date(), code: response.statusCode, headers: headers, body: nil)

    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        guard let error = error else { return }
        client?.urlProtocol(self, didFailWithError: error)
    }
}

extension URLSessionConfiguration {
    @objc class func captainsLogDefaultSessionConfiguration() -> URLSessionConfiguration {
        let configuration = captainsLogDefaultSessionConfiguration()
        configuration.protocolClasses?.insert(CaptainsLogHTTPProtocol.self, at: 0)
        return configuration
    }

    @objc class func captainsLogEphemeralSessionConfiguration() -> URLSessionConfiguration {
        let configuration = captainsLogEphemeralSessionConfiguration()
        configuration.protocolClasses?.insert(CaptainsLogHTTPProtocol.self, at: 0)
        return configuration
    }
}
