//
//  StreamingSplitKillTest.swift
//  SplitTests
//
//  Created by Javier L. Avrudsky on 16/10/2020.
//  Copyright © 2020 Split. All rights reserved.
//

import XCTest
@testable import Split

class StreamingSplitKillTest: XCTestCase {
    var httpClient: HttpClient!
    let apiKey = IntegrationHelper.dummyApiKey
    let userKey = IntegrationHelper.dummyUserKey
    var streamingBinding: TestStreamResponseBinding?
    let sseConnExp = XCTestExpectation(description: "sseConnExp")
    var splitsChangesHits = 0
    var numbers = [500, 1000, 2000, 3000, 4000]
    var changes = [String]()
    var exps = [XCTestExpectation]()
    let kInitialChangeNumber = 1000
    var expIndex: Int = 0
    var queue = DispatchQueue(label: "hol", qos: .userInteractive)

    var exp1: XCTestExpectation!
    var exp2: XCTestExpectation!
    var exp3: XCTestExpectation!
    var exp4: XCTestExpectation!

    override func setUp() {
        expIndex = 1
        let session = HttpSessionMock()
        let reqManager = HttpRequestManagerTestDispatcher(dispatcher: buildTestDispatcher(),
                                                          streamingHandler: buildStreamingHandler())
        httpClient = DefaultHttpClient(session: session, requestManager: reqManager)
        loadChanges()
    }

    func testSplitKill() {
        let splitConfig: SplitClientConfig = SplitClientConfig()
        splitConfig.featuresRefreshRate = 9999
        splitConfig.segmentsRefreshRate = 9999
        splitConfig.impressionRefreshRate = 999999
        splitConfig.sdkReadyTimeOut = 60000
        splitConfig.eventsPushRate = 999999
        //splitConfig.isDebugModeEnabled = true

        let key: Key = Key(matchingKey: userKey)
        let builder = DefaultSplitFactoryBuilder()
        _ = builder.setHttpClient(httpClient)
        _ = builder.setReachabilityChecker(ReachabilityMock())
        let factory = builder.setApiKey(apiKey).setKey(key)
            .setConfig(splitConfig).build()!

        let client = factory.client
        let expTimeout:  TimeInterval = 5

        let sdkReadyExpectation = XCTestExpectation(description: "SDK READY Expectation")
        exp1 = XCTestExpectation(description: "Exp1")
        exp2 = XCTestExpectation(description: "Exp2")
        exp3 = XCTestExpectation(description: "Exp3")
        exp4 = XCTestExpectation(description: "Exp4")

        client.on(event: SplitEvent.sdkReady) {
            IntegrationHelper.tlog("READY")
            sdkReadyExpectation.fulfill()
        }

        client.on(event: SplitEvent.sdkReadyTimedOut) {
            IntegrationHelper.tlog("TIMEOUT")
        }

        wait(for: [sdkReadyExpectation, sseConnExp], timeout: expTimeout)
        
        IntegrationHelper.tlog("KEEPAL")
        streamingBinding?.push(message: ":keepalive") // send keep alive to confirm streaming connection ok
        wait(for: [exp1], timeout: expTimeout)
        waitForUpdate(secs: 1)

        let splitName = "workm"
        let treatmentReady = client.getTreatment(splitName)

        streamingBinding?.push(message:
            StreamingIntegrationHelper.splitKillMessagge(splitName: splitName, defaultTreatment: "conta",
                                                         timestamp: numbers[splitsChangesHits],
                                                         changeNumber: numbers[splitsChangesHits]))

        wait(for: [exp2], timeout: expTimeout)
        waitForUpdate(secs: 1)
        
        let treatmentKill = client.getTreatment(splitName)

        print("Updating split")
        streamingBinding?.push(message:
            StreamingIntegrationHelper.splitUpdateMessage(timestamp: numbers[splitsChangesHits],
                                                          changeNumber: numbers[splitsChangesHits]))

        wait(for: [exp3], timeout: expTimeout)
        waitForUpdate(secs: 1)
        let treatmentNoKill = client.getTreatment(splitName)
        
        streamingBinding?.push(message:
            StreamingIntegrationHelper.splitKillMessagge(splitName: splitName, defaultTreatment: "conta",
                                                         timestamp: numbers[0],
                                                         changeNumber: numbers[0]))

        ThreadUtils.delay(seconds: 2.0) // The server should not be hit here
        let treatmentOldKill = client.getTreatment(splitName)

        XCTAssertEqual("on", treatmentReady)
        XCTAssertEqual("conta", treatmentKill)
        XCTAssertEqual("on", treatmentNoKill)
        XCTAssertEqual("on", treatmentOldKill)
    }
    
    private func getChanges(for hitNumber: Int) -> Data {
        if hitNumber < 4 {
            return Data(self.changes[hitNumber].utf8)
        }
        return Data(IntegrationHelper.emptySplitChanges(since: 999999, till: 999999).utf8)
    }

    private func buildTestDispatcher() -> HttpClientTestDispatcher {
        return { request in
            switch request.url.absoluteString {
            case let(urlString) where urlString.contains("splitChanges"):
                let hitNumber = self.getAndUpdateHit()
                IntegrationHelper.tlog("sc hit: \(hitNumber)")
                switch hitNumber {
                case 1:
                    self.exp1.fulfill()
                case 2:
                    self.exp2.fulfill()
                case 3:
                    self.exp3.fulfill()
                default:
                    IntegrationHelper.tlog("Exp no fired \(hitNumber)")
                }
                return TestDispatcherResponse(code: 200, data: self.getChanges(for: hitNumber))

            case let(urlString) where urlString.contains("mySegments"):
                return TestDispatcherResponse(code: 200, data: Data(IntegrationHelper.emptyMySegments.utf8))

            case let(urlString) where urlString.contains("auth"):
                return TestDispatcherResponse(code: 200, data: Data(IntegrationHelper.dummySseResponse().utf8))
            default:
                return TestDispatcherResponse(code: 500)
            }
        }
    }
    
    private func getAndUpdateHit() -> Int {
        var hitNumber = 0
        DispatchQueue.global().sync {
            hitNumber = self.splitsChangesHits
            self.splitsChangesHits+=1
        }
        return hitNumber
    }

    private func buildStreamingHandler() -> TestStreamResponseBindingHandler {
        return { request in
            self.streamingBinding = TestStreamResponseBinding.createFor(request: request, code: 200)
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                self.sseConnExp.fulfill()
            }
            return self.streamingBinding!
        }
    }

    private func getChanges(killed: Bool, since: Int, till: Int) -> String {
        let change = IntegrationHelper.getChanges(fileName: "simple_split_change")
        change?.since = Int64(since)
        change?.till = Int64(till)
        let split = change?.splits[0]
        split?.changeNumber = Int64(since)
        if killed {
            split?.killed = true
            split?.defaultTreatment = "conta"
        }
        return (try? Json.encodeToJson(change)) ?? ""
    }

    private func loadChanges() {
        for i in 0..<4 {
            let change = getChanges(killed: (i == 2),
                                    since: self.numbers[i],
                                    till: self.numbers[i])
            changes.insert(change, at: i)
        }
    }
    
    private func waitForUpdate(secs: UInt32 = 2) {
        sleep(secs)
    }
}



