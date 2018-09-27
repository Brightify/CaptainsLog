//
//  CaptainsLogDestination.swift
//  CaptainsLog-macOS
//
//  Created by Robin Krenecky on 26/09/2018.
//  Copyright © 2018 Brightify. All rights reserved.
//

import SwiftyBeaver

public class CaptainsLogDestination: BaseDestination {
    private let captainsLogBaseURL: URL
    private let port = 1111
    private let applicationId: String

    public init(captainsLogBaseURL: String) {
        var components = URLComponents(string: captainsLogBaseURL)!
        components.port = 1111

        self.captainsLogBaseURL = components.url!
        self.applicationId = Bundle.main.infoDictionary![kCFBundleNameKey as String] as! String

        super.init()

        try! register()
    }
    
    public override func send(_ level: SwiftyBeaver.Level, msg: String, thread: String,
                              file: String, function: String, line: Int, context: Any?) -> String? {
        let logItem = LogItem(id: UUID().uuidString,
                              kind: .log(Log(time: Date(),
                                             level: LogLevel(rawValue: level.rawValue) ?? .verbose,
                                             message: msg,
                                             thread: thread,
                                             file: file,
                                             function: function,
                                             line: line)))

        try? post(to: "api/runs/\(CaptainsLog.instance.uuid)/logItems", value: logItem)
        
        return msg
    }

    private func register() throws {
        let appRun = ApplicationRun(
            id: CaptainsLog.instance.uuid,
            name: Bundle.main.infoDictionary![kCFBundleNameKey as String] as! String,
            identifier: Bundle.main.bundleIdentifier!,
            version: Bundle.main.infoDictionary![kCFBundleVersionKey as String] as! String,
            date: Date()
        )

        try post(to: "api/runs", value: appRun)
    }

    private func post<T: Encodable>(to endpoint: String, value: T) throws {
        let url = captainsLogBaseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(value)

        URLSession.shared.dataTask(with: request) { data, response, error in
            // TODO Handle the response
        }.resume()
    }
}
