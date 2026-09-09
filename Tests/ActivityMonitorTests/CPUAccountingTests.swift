import SystemBridge
import XCTest

@testable import ActivityMonitor

final class CPUAccountingTests: XCTestCase {
  func testProcessRatesAreNotCappedAtOneProcessor() {
    var before = AMProcess()
    before.accessible = 1
    before.start = 42
    before.cpu = 2_000_000_000
    var after = before
    for processors in [1, 4, 10] {
      after.cpu = before.cpu + UInt64(processors) * 2_000_000_000
      XCTAssertEqual(
        CPUAccounting.processPercent(current: after, previous: before, elapsed: 2),
        Double(processors) * 100, accuracy: 0.0001)
    }
    after.cpu = before.cpu + 2_500_000_000
    XCTAssertEqual(CPUAccounting.processPercent(current: after, previous: before, elapsed: 1), 250)
  }
  func testMissingReusedAndResetProcessBaselinesDoNotCreateSpikes() {
    var before = AMProcess()
    before.accessible = 1
    before.start = 42
    before.cpu = 2_000_000_000
    var after = before
    after.cpu = 3_000_000_000
    XCTAssertEqual(CPUAccounting.processPercent(current: after, previous: nil, elapsed: 1), 0)
    before.accessible = 0
    XCTAssertEqual(CPUAccounting.processPercent(current: after, previous: before, elapsed: 1), 0)
    before.accessible = 1
    after.accessible = 0
    XCTAssertEqual(CPUAccounting.processPercent(current: after, previous: before, elapsed: 1), 0)
    after.accessible = 1
    after.start = 43
    XCTAssertEqual(CPUAccounting.processPercent(current: after, previous: before, elapsed: 1), 0)
    after.start = before.start
    after.cpu = 1
    XCTAssertEqual(CPUAccounting.processPercent(current: after, previous: before, elapsed: 1), 0)
    XCTAssertEqual(CPUAccounting.processPercent(current: before, previous: before, elapsed: 0), 0)
    XCTAssertEqual(
      CPUAccounting.processPercent(current: before, previous: before, elapsed: .nan), 0)
  }
  func testSystemCapacityStaysNormalizedAcrossProcessorCountsAndTickWrap() {
    for processors in [1, 4, 10] {
      let before = AMSystem()
      var after = before
      after.user = UInt64(60 * processors)
      after.system = UInt64(15 * processors)
      after.idle = UInt64(25 * processors)
      let usage = CPUAccounting.systemPercent(current: after, previous: before)
      XCTAssertEqual(usage.user, 60)
      XCTAssertEqual(usage.system, 15)
      XCTAssertEqual(usage.idle, 25)
      XCTAssertEqual(usage.user + usage.system + usage.idle, 100)
    }
    var before = AMSystem()
    before.user = UInt64(UInt32.max) - 9
    var after = AMSystem()
    after.user = 10
    after.system = 10
    after.idle = 10
    let usage = CPUAccounting.systemPercent(current: after, previous: before)
    XCTAssertEqual(usage.user, 50)
    XCTAssertEqual(usage.system, 25)
    XCTAssertEqual(usage.idle, 25)
  }
  func testApplicationWorkloadChartPreservesMulticoreValues() {
    let samples = TelemetryData.samples(
      points: [Point(date: Date(), a: 1000, b: 0)], metric: .energy, maximumGap: 10)
    XCTAssertEqual(samples.first?.value, 1000)
    XCTAssertGreaterThan(TelemetryData.domain(samples, metric: .energy).upperBound, 1000)
  }
  @MainActor func testOneSecondDefaultAndSlowerOptionsRemainAvailable() {
    let monitor = Monitor(startAutomatically: false)
    XCTAssertEqual(monitor.interval, 1)
    monitor.interval = 2
    XCTAssertEqual(monitor.interval, 2)
    monitor.interval = 5
    XCTAssertEqual(monitor.interval, 5)
  }
}
