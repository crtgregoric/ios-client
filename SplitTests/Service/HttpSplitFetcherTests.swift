//
//  HttpSplitFetcherTests.swift
//  SplitTests
//
//  Created by Javier Avrudsky on 02/12/2020.
//  Copyright © 2020 Split. All rights reserved.
//

import Foundation

import XCTest
@testable import Split

class HttpSplitFetcherTests: XCTestCase {
    
    var restClient: RestClientStub!
    var fetcher: HttpSplitFetcher!
    var metricsManager: MetricsManagerStub!
    
    override func setUp() {
        restClient = RestClientStub()
        metricsManager = MetricsManagerStub()
        fetcher = DefaultHttpSplitFetcher(restClient: restClient, metricsManager: metricsManager)
    }
    
    func testServerNoReachable() {
        restClient.isServerAvailable = false
        var isError = false
        do {
            let _ = try fetcher.execute(since: 1, headers: nil)
        } catch {
            isError = true
        }
        XCTAssertTrue(isError)
        XCTAssertFalse(metricsManager.countCalled)
        XCTAssertFalse(metricsManager.timeCalled)
    }
    
    func testSuccessFullFetch() throws {
        restClient.isServerAvailable = true
        restClient.update(changes: [newChange(since: 1, till: 2), newChange(since: 2, till: 2)])
        
        let c = try fetcher.execute(since: 1, headers: nil)
        
        XCTAssertEqual(1, c.since)
        XCTAssertEqual(2, c.till)
        XCTAssertEqual(0, c.splits.count)
        XCTAssertTrue(metricsManager.countCalled)
        XCTAssertTrue(metricsManager.timeCalled)
    }
    
    func newChange(since: Int64, till: Int64, splits: [Split] = []) -> SplitChange {
        return SplitChange(splits: [], since: since, till: till)
    }

    override func tearDown() {
    }
}

