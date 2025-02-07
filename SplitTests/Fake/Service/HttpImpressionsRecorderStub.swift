//
//  HttpImpressionsRecorderStub.swift
//  SplitTests
//
//  Created by Javier Avrudsky on 18/12/2020.
//  Copyright © 2020 Split. All rights reserved.
//

import Foundation
@testable import Split

class HttpImpressionsRecorderStub: HttpImpressionsRecorder {

    var impressionsSent = [ImpressionsTest]()
    var errorOccurredCallCount = -1
    var executeCallCount = 0

    func execute(_ items: [ImpressionsTest]) throws {
        executeCallCount+=1
        if errorOccurredCallCount == executeCallCount {
            throw HttpError.unknown(message: "something happend")
        }
        impressionsSent.append(contentsOf: items)
    }
}
