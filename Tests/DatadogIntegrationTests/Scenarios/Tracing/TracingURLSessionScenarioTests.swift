/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import HTTPServerMock
import XCTest

private extension ExampleApplication {
    func tapSend3rdPartyRequests() {
        buttons["Send 3rd party requests"].tap()
    }
}

class TracingURLSessionScenarioTests: IntegrationTests, TracingCommonAsserts {
    func testTracingURLSessionScenario() throws {
        try runTest(for: TracingURLSessionScenario.self)
    }

    func testTracingNSURLSessionScenario() throws {
        try runTest(for: TracingNSURLSessionScenario.self)
    }

    /// Both, `URLSession` (Swift) and `NSURLSession` (Objective-C) scenarios fetch exactly the same
    /// resources, so we can run the same test and assertions.
    private func runTest(for scenario: TestScenario.Type) throws {
        let testBeginTimeInNanoseconds = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)

        // Server session recording first party requests send to `HTTPServerMock`.
        // Used to assert that trace propagation headers are send for first party requests.
        let customFirstPartyServerSession = server.obtainUniqueRecordingSession()

        // Server session recording `Spans` send to `HTTPServerMock`.
        let tracingServerSession = server.obtainUniqueRecordingSession()

        // Requesting this first party by the app should create the `Span`.
        let firstPartyGETResourceURL = URL(
            string: customFirstPartyServerSession.recordingURL.deletingLastPathComponent().absoluteString + "inspect"
        )!
        // Requesting this first party by the app should create the `Span`.
        let firstPartyPOSTResourceURL = customFirstPartyServerSession.recordingURL
        // Requesting this first party by the app should create the `Span` with error.
        let firstPartyBadResourceURL = URL(string: "https://foo.bar")!

        // Requesting this third party by the app should NOT create the `Span`.
        let thirdPartyGETResourceURL = URL(string: "https://bitrise.io")!
        // Requesting this third party by the app should NOT create the `Span`.
        let thirdPartyPOSTResourceURL = URL(string: "https://bitrise.io/about")!

        let app = ExampleApplication()
        app.launchWith(
            testScenario: scenario,
            serverConfiguration: HTTPServerMockConfiguration(
                tracesEndpoint: tracingServerSession.recordingURL,
                instrumentedEndpoints: [
                    firstPartyGETResourceURL,
                    firstPartyPOSTResourceURL,
                    firstPartyBadResourceURL,
                    thirdPartyGETResourceURL,
                    thirdPartyPOSTResourceURL
                ]
            )
        )
        app.tapSend3rdPartyRequests()

        // Get Tracing requests
        let recordedTracingRequests = try tracingServerSession
            .pullRecordedPOSTRequests(count: 1, timeout: dataDeliveryTimeout)

        let testEndTimeInNanoseconds = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)

        // Get `Spans`
        let spanMatchers = try recordedTracingRequests
            .flatMap { request in try SpanMatcher.fromNewlineSeparatedJSONObjectsData(request.httpBody) }

        // Assert common things
        assertHTTPHeadersAndPath(in: recordedTracingRequests)
        try assertCommonMetadata(in: spanMatchers)
        try assertThat(spans: spanMatchers, startAfter: testBeginTimeInNanoseconds, andFinishBefore: testEndTimeInNanoseconds)

        let taskWithURL = try XCTUnwrap(
            spanMatchers.first { span in try span.resource() == firstPartyGETResourceURL.absoluteString },
            "`Span` should be send for `firstPartyGETResourceURL`"
        )
        let taskWithRequest = try XCTUnwrap(
            spanMatchers.first { span in try span.resource() == firstPartyPOSTResourceURL.absoluteString },
            "`Span` should be send for `firstPartyPOSTResourceURL`"
        )
        let taskWithBadURL = try XCTUnwrap(
            spanMatchers.first { span in try span.resource() == firstPartyBadResourceURL.absoluteString },
            "`Span` should be send for `firstPartyBadResourceURL`"
        )
        try XCTAssertFalse(
            spanMatchers.contains { span in try span.resource() == thirdPartyGETResourceURL.absoluteString },
            "`Span` should NOT bet send for `thirdPartyGETResourceURL`"
        )
        try XCTAssertFalse(
            spanMatchers.contains { span in try span.resource() == thirdPartyPOSTResourceURL.absoluteString },
            "`Span` should NOT bet send for `thirdPartyPOSTResourceURL`"
        )

        XCTAssertEqual(spanMatchers.count, 3, "There should be only 3 `Spans` send")

        XCTAssertEqual(try taskWithURL.operationName(), "urlsession.request")
        XCTAssertEqual(try taskWithRequest.operationName(), "urlsession.request")
        XCTAssertEqual(try taskWithBadURL.operationName(), "urlsession.request")

        XCTAssertEqual(try taskWithURL.metrics.isRootSpan(), 1)
        XCTAssertEqual(try taskWithRequest.metrics.isRootSpan(), 1)
        XCTAssertEqual(try taskWithBadURL.metrics.isRootSpan(), 1)

        XCTAssertEqual(try taskWithURL.isError(), 0)
        XCTAssertEqual(try taskWithRequest.isError(), 0)
        XCTAssertEqual(try taskWithBadURL.isError(), 1)

        XCTAssertGreaterThan(try taskWithURL.duration(), 0)
        XCTAssertGreaterThan(try taskWithRequest.duration(), 0)
        XCTAssertGreaterThan(try taskWithBadURL.duration(), 0)

        // Assert tracing HTTP headers propagated to `firstPartyPOSTResourceURL`
        let firstPartyRequests = try customFirstPartyServerSession
            .pullRecordedPOSTRequests(count: 1, timeout: dataDeliveryTimeout)

        XCTAssertEqual(firstPartyRequests.count, 1)

        let firstPartyRequest = firstPartyRequests[0]
        let expectedTraceIDHeader = "x-datadog-trace-id: \(try taskWithRequest.traceID().hexadecimalNumberToDecimal)"
        let expectedSpanIDHeader = "x-datadog-parent-id: \(try taskWithRequest.spanID().hexadecimalNumberToDecimal)"
        XCTAssertTrue(
            firstPartyRequest.httpHeaders.contains(expectedTraceIDHeader),
            """
            Request `\(firstPartyRequest.path)` does not contain `\(expectedTraceIDHeader)` header.
            - request.headers: \(firstPartyRequest.httpHeaders)
            """
        )
        XCTAssertTrue(
            firstPartyRequest.httpHeaders.contains(expectedSpanIDHeader),
            """
            Request `\(firstPartyRequest.path)` does not contain `\(expectedSpanIDHeader)` header.
            - request.headers: \(firstPartyRequest.httpHeaders)
            """
        )
    }
}
