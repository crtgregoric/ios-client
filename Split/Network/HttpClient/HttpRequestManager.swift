//
//  HttpRequestManager.swift
//  Split
//
//  Created by Javier L. Avrudsky on 08/07/2020.
//  Copyright © 2020 Split. All rights reserved.
//

import Foundation

protocol HttpRequestManager {
    func addRequest(_ request: HttpRequest)
    func append(data: Data, to taskIdentifier: Int)
    func complete(taskIdentifier: Int, error: HttpError?)
    func set(responseCode: Int, to taskIdentifier: Int) -> Bool
}

class DefaultHttpRequestManager: NSObject {

    var requests = HttpRequestList()
}

// MARK: HttpRequestManager - URLSessionTaskDelegate
extension DefaultHttpRequestManager: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        var httpError: HttpError?
        if let error = error {
            httpError = HttpError.unknown(message: error.localizedDescription)
        }
        complete(taskIdentifier: task.taskIdentifier, error: httpError)
    }
}

// MARK: HttpUrlSessionDelegate - URLSessionDataDelegate
extension DefaultHttpRequestManager: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {

        if let urlResponse = response as? HTTPURLResponse {
            if set(responseCode: urlResponse.statusCode, to: dataTask.taskIdentifier) {
                completionHandler(.allow)
            } else {
                completionHandler(.allow)
            }
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        append(data: data, to: dataTask.taskIdentifier)
    }
}

extension DefaultHttpRequestManager: HttpRequestManager {
    func set(responseCode: Int, to taskIdentifier: Int) -> Bool {
        if let request = requests.get(identifier: taskIdentifier) {
            request.setResponse(code: responseCode)
            return true
        }
        return false
    }

    func complete(taskIdentifier: Int, error: HttpError?) {
        if let request = requests.get(identifier: taskIdentifier) {
            request.complete(error: error)
        }
    }

    func addRequest(_ request: HttpRequest) {
        requests.set(request)
    }

    func append(data: Data, to taskIdentifier: Int) {
        // TODO: Check this if and class hiearchy
        if let request = requests.get(identifier: taskIdentifier) as? HttpDataRequestWrapper {
            request.notifyIncomingData(data)
        } else if let request = requests.get(identifier: taskIdentifier) as? HttpStreamRequest {
            request.notifyIncomingData(data)
        }
    }
}
