import XCTest
@testable import ActivityMonitor

final class ANEProfilerTests: XCTestCase {
  private let toc = Data("""
    <trace-toc><run number="1"><info><summary><duration>2.0</duration>
    </summary></info></run></trace-toc>
    """.utf8)

  func testIntervalsReportMeasuredTimeWithoutDoubleCountingOverlap() throws {
    let xml = Data("""
      <trace-query-result><node><schema name="ane-hw-intervals-internal"/>
        <row><start-time>500000000</start-time><duration>400000000</duration>
          <metal-nesting-level>0</metal-nesting-level>
          <formatted-label id="1" fmt="Neural Engine Prediction"/>
          <gpu-state id="2" fmt="Active"/></row>
        <row><start-time>700000000</start-time><duration>400000000</duration>
          <metal-nesting-level>0</metal-nesting-level>
          <formatted-label ref="1"/><gpu-state ref="2"/></row>
        <row><start-time>1500000000</start-time><duration id="3">200000000</duration>
          <metal-nesting-level>0</metal-nesting-level>
          <formatted-label fmt="Neural Engine Load"/><gpu-state ref="2"/></row>
        <row><start-time>1500000000</start-time><duration ref="3"/>
          <metal-nesting-level>0</metal-nesting-level>
          <formatted-label fmt="Neural Engine Load"/><gpu-state ref="2"/></row>
      </node></trace-query-result>
      """.utf8)
    let result = try ANETraceParser.parse(toc: toc, intervals: xml)
    XCTAssertEqual(result.activeSeconds, 0.8, accuracy: 1e-9)
    XCTAssertEqual(result.observedActivityPercent, 40, accuracy: 1e-9)
    XCTAssertEqual(result.predictionCount, 2)
    XCTAssertEqual(result.averagePredictionMilliseconds ?? -1, 400, accuracy: 1e-9)
  }

  func testValidEmptyCaptureReportsNoObservedActivity() throws {
    let xml = Data("""
      <trace-query-result><node><schema name="ane-hw-intervals-internal"/>
      </node></trace-query-result>
      """.utf8)
    let result = try ANETraceParser.parse(toc: toc, intervals: xml)
    XCTAssertEqual(result.observedActivityPercent, 0)
    XCTAssertEqual(result.predictionCount, 0)
    XCTAssertNil(result.averagePredictionMilliseconds)
  }

  func testResultUsesActualTraceEndTime() throws {
    let datedTOC = Data("""
      <trace-toc><run number="1"><info><summary>
      <duration>2.0</duration><end-date>2026-09-15T10:02:42.974+02:00</end-date>
      </summary></info></run></trace-toc>
      """.utf8)
    let xml = Data("""
      <trace-query-result><node><schema name="ane-hw-intervals-internal"/>
      </node></trace-query-result>
      """.utf8)
    let result = try ANETraceParser.parse(toc: datedTOC, intervals: xml)
    let expected = ISO8601DateFormatter()
    expected.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    XCTAssertEqual(result.recordedAt,
      try XCTUnwrap(expected.date(from: "2026-09-15T10:02:42.974+02:00")))
  }

  func testUnknownInstrumentExportFailsClearly() {
    let xml = Data("""
      <trace-query-result><node><schema name="some-new-schema"/>
      </node></trace-query-result>
      """.utf8)
    XCTAssertThrowsError(try ANETraceParser.parse(toc: toc, intervals: xml)) {
      guard case ANEProfileError.unsupportedExport = $0 else {
        return XCTFail("Expected an unsupported export error")
      }
    }
  }

  func testLocalInstrumentsExportWhenSupplied() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let tocPath = environment["AM_ANE_PROFILE_TOC"],
      let intervalsPath = environment["AM_ANE_PROFILE_INTERVALS"]
    else { throw XCTSkip("Set export paths to validate an on-device ANE trace") }
    let result = try ANETraceParser.parse(
      toc: Data(contentsOf: URL(fileURLWithPath: tocPath)),
      intervals: Data(contentsOf: URL(fileURLWithPath: intervalsPath)))
    XCTAssertGreaterThan(result.predictionCount, 0)
    XCTAssertGreaterThan(result.activeSeconds, 0)
    XCTAssertGreaterThan(result.averagePredictionMilliseconds ?? 0, 0)
    XCTAssertLessThanOrEqual(result.observedActivityPercent, 100)
  }

  func testLocalRecorderWhenRequested() throws {
    guard ProcessInfo.processInfo.environment["AM_ANE_RUN_CAPTURE"] == "1" else {
      throw XCTSkip("Set AM_ANE_RUN_CAPTURE=1 for an on-device Instruments recording")
    }
    let result = try ANEInstrumentsProfiler().capture()
    XCTAssertGreaterThan(result.durationSeconds, 0)
    XCTAssertLessThanOrEqual(result.observedActivityPercent, 100)
  }
}
