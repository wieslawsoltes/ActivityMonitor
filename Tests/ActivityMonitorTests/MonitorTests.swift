import Darwin
import SystemBridge
import XCTest

@testable import ActivityMonitor

final class MonitorTests: XCTestCase {
  func testLiveCollectorFindsSelfAndPhysicalMemory() {
    let snapshot = Collector().collect()
    XCTAssertTrue(snapshot.processes.contains { $0.id == getpid() })
    XCTAssertTrue(
      snapshot.processes.contains { $0.id == 1 && $0.uid == 0 },
      "Protected processes must remain visible")
    XCTAssertGreaterThan(snapshot.system.physical, 0)
    let own = snapshot.processes.first { $0.id == getpid() }!
    XCTAssertGreaterThan(own.memory, 0)
    XCTAssertGreaterThan(own.threads, 0)
    XCTAssertEqual(own.uid, getuid())
    XCTAssertFalse(own.name.isEmpty)
  }
  func testCPUCounterDeltaIsFiniteAndNonnegative() {
    let collector = Collector()
    _ = collector.collect()
    var accumulator = 0.0
    for i in 1...100000 { accumulator += sqrt(Double(i)) }
    XCTAssertGreaterThan(accumulator, 0)
    let rows = collector.collect().processes
    XCTAssertTrue(rows.allSatisfy { $0.cpu.isFinite && $0.cpu >= 0 })
    XCTAssertGreaterThan(rows.first { $0.id == getpid() }!.cpu, 0)
  }
  func testCSVQuotingPreservesCommasQuotesAndNewlines() {
    XCTAssertEqual(csvCell("a,\"b\"\nc"), "\"a,\"\"b\"\"\nc\"")
  }
  func testDurationIncludesHours() {
    XCTAssertEqual(duration(3661), "1:01:01")
    XCTAssertEqual(duration(-2), "0:00:00")
  }
  func testSystemCountersAreCoherent() {
    var s = AMSystem()
    am_system(&s)
    XCTAssertGreaterThan(s.user + s.system + s.idle, 0)
    XCTAssertLessThanOrEqual(s.wired, s.physical)
    XCTAssertTrue((-1...100).contains(s.battery))
  }
  func testCPUTimeMatchesGetrusageSeconds() {
    var accumulator = 0.0
    for i in 1...2_000_000 { accumulator += sqrt(Double(i)) }
    XCTAssertGreaterThan(accumulator, 0)
    let own = Collector().collect().processes.first { $0.id == getpid() }!
    var usage = rusage()
    XCTAssertEqual(getrusage(RUSAGE_SELF, &usage), 0)
    let expected =
      Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(
        usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    XCTAssertEqual(own.cpuTime, expected, accuracy: max(0.02, expected * 0.15))
  }
  @MainActor func testTerminationRejectsReusedIdentityAndSelf() throws {
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/bin/sleep")
    child.arguments = ["30"]
    try child.run()
    defer {
      if child.isRunning {
        child.terminate()
        child.waitUntilExit()
      }
    }
    let snapshot = Collector().collect()
    var row = try XCTUnwrap(snapshot.processes.first { $0.id == child.processIdentifier })
    XCTAssertTrue(processStillMatches(row))
    let monitor = Monitor(startAutomatically: false)
    row.start += 1
    monitor.terminate(row, force: true)
    XCTAssertNotNil(monitor.error)
    XCTAssertTrue(child.isRunning)
    let own = try XCTUnwrap(snapshot.processes.first { $0.id == getpid() })
    monitor.error = nil
    monitor.terminate(own, force: true)
    XCTAssertNotNil(monitor.error)
  }
  @MainActor func testQuitStopsOnlyOwnedTestChild() throws {
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/bin/sleep")
    child.arguments = ["30"]
    try child.run()
    defer {
      if child.isRunning {
        child.terminate()
        child.waitUntilExit()
      }
    }
    let row = try XCTUnwrap(
      Collector().collect().processes.first { $0.id == child.processIdentifier })
    let monitor = Monitor(startAutomatically: false)
    monitor.terminate(row, force: false)
    child.waitUntilExit()
    XCTAssertNil(monitor.error)
    XCTAssertEqual(child.terminationReason, .uncaughtSignal)
    XCTAssertEqual(child.terminationStatus, SIGTERM)
  }
  func testRestrictedMetricsExportAsEmptyCells() throws {
    var row = try XCTUnwrap(Collector().collect().processes.first { $0.id == getpid() })
    row.networkReceived = nil
    row.networkSent = nil
    row.accessible = false
    row.ioAccessible = false
    XCTAssertTrue(processCSV([row]).hasSuffix(",,,,,,"))
  }

  func testNetworkParserHandlesCommasDotsAndInvalidRows() {
    let parsed = parseProcessNetwork(
      ",bytes_in,bytes_out,\ncom.app.helper.123,100,200,\napp, with comma.456,1234,5678,\nbad,invalid,9,\n"
    )
    XCTAssertEqual(parsed.count, 2)
    XCTAssertEqual(parsed[123]?.received, 100)
    XCTAssertEqual(parsed[123]?.sent, 200)
    XCTAssertEqual(parsed[456]?.received, 1234)
  }
  func testNetworkCSVRetainsByteCounters() throws {
    var row = try XCTUnwrap(Collector().collect().processes.first { $0.id == getpid() })
    row.networkReceived = 1234
    row.networkSent = 5678
    XCTAssertTrue(processCSV([row]).hasSuffix(",1234,5678"))
  }

}
