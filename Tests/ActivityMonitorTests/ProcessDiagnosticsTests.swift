import AppKit
import Darwin
import SwiftUI
import SystemBridge
import XCTest

@testable import ActivityMonitor

final class ProcessDiagnosticsTests: XCTestCase {
  func ownRow() throws -> ProcessRow {
    // These tests need a real PID/start pair, not network, GPU, user-directory,
    // or power-service collection from every process on the host.
    var start: UInt64 = 0
    XCTAssertEqual(am_process_identity(getpid(), &start), 0)
    var row = PerformanceFixture.rows(1)[0]
    row.id = getpid()
    row.uid = getuid()
    row.start = start
    row.accessible = true
    return row
  }
  func testIdentityRejectsReuseAndExit() throws {
    var row = try ownRow()
    XCTAssertTrue(ProcessIdentity(row).matches())
    row.start += 1
    XCTAssertFalse(ProcessIdentity(row).matches())
    XCTAssertFalse(DiagnosticCollector.read(identity: ProcessIdentity(row), tab: .files).valid)
    var info = AMProcessInfo()
    XCTAssertNotEqual(am_process_info(Int32.max, &info), 0)
  }
  func testDiagnosticCPUTimeMatchesGetrusageSeconds() {
    func seconds(_ usage: rusage) -> Double {
      Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
    var before = rusage()
    var after = rusage()
    var info = AMProcessInfo()
    XCTAssertEqual(getrusage(RUSAGE_SELF, &before), 0)
    XCTAssertEqual(am_process_info(getpid(), &info), 0)
    XCTAssertEqual(info.taskError, 0)
    XCTAssertEqual(getrusage(RUSAGE_SELF, &after), 0)
    let measured = Double(info.userNS + info.systemNS) / 1e9
    XCTAssertGreaterThanOrEqual(measured, seconds(before) - 0.005)
    XCTAssertLessThanOrEqual(measured, seconds(after) + 0.005)
  }
  func testThreadIDsAndNanosecondAccountingMatchKernel() throws {
    var tid: UInt64 = 0
    XCTAssertEqual(pthread_threadid_np(nil, &tid), 0)
    var before = proc_threadinfo()
    var after = proc_threadinfo()
    let size = Int32(MemoryLayout<proc_threadinfo>.size)
    XCTAssertEqual(proc_pidinfo(getpid(), PROC_PIDTHREADID64INFO, tid, &before, size), size)
    var threads = [AMThread](repeating: AMThread(), count: 4096)
    var count: Int32 = 0
    var truncated: Int32 = 0
    XCTAssertEqual(am_process_threads(getpid(), &threads, 4096, &count, &truncated), 0)
    let own = try XCTUnwrap(threads.prefix(Int(count)).first { $0.id == tid && $0.uniqueID != 0 })
    XCTAssertEqual(proc_pidinfo(getpid(), PROC_PIDTHREADID64INFO, tid, &after, size), size)
    XCTAssertEqual(own.error, 0)
    XCTAssertGreaterThanOrEqual(own.userNS, before.pth_user_time)
    XCTAssertLessThanOrEqual(own.userNS, after.pth_user_time)
    XCTAssertGreaterThanOrEqual(own.systemNS, before.pth_system_time)
    XCTAssertLessThanOrEqual(own.systemNS, after.pth_system_time)
    XCTAssertEqual(Set(threads.prefix(Int(count)).map(\.id)).count, Int(count))
    XCTAssertEqual(truncated, 0)
  }
  func testOpenFileAndTCPListenerAreStructuredAndNotConfusedWithMachPorts() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "diagnostic-\(UUID()).txt")
    try Data("known file".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    let socketFD = socket(AF_INET, SOCK_STREAM, 0)
    XCTAssertGreaterThanOrEqual(socketFD, 0)
    defer { close(socketFD) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    XCTAssertEqual(bound, 0)
    XCTAssertEqual(listen(socketFD, 1), 0)
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socketFD, $0, &length) }
    }
    let files = DiagnosticCollector.files(getpid(), socketsOnly: false)
    let entry = try XCTUnwrap(files.records.first { $0.id == String(file.fileDescriptor) })
    XCTAssertTrue(entry.path?.hasSuffix(url.lastPathComponent) == true)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    XCTAssertEqual(
      entry.numbers["Inode"], (attributes[.systemFileNumber] as? NSNumber)?.doubleValue)
    XCTAssertEqual(entry.numbers["Size"], 10)
    let sockets = DiagnosticCollector.files(getpid(), socketsOnly: true)
    let listener = try XCTUnwrap(sockets.records.first { $0.id == String(socketFD) })
    XCTAssertEqual(
      listener.cells["Local endpoint"], "127.0.0.1:\(UInt16(bigEndian:address.sin_port))")
    XCTAssertEqual(listener.cells["Protocol"], "TCP")
    XCTAssertEqual(listener.cells["State"], "Listen")
    let ports = DiagnosticCollector.ports(getpid())
    XCTAssertFalse(ports.records.isEmpty, ports.status)
    XCTAssertTrue(ports.columns.contains("Rights"))
    XCTAssertFalse(ports.columns.contains("Local endpoint"))
  }
  func testRegionTraversalAndCollectionLimits() throws {
    let section = DiagnosticCollector.regions(getpid())
    XCTAssertFalse(section.records.isEmpty, section.status)
    XCTAssertTrue(section.records.allSatisfy { ($0.numbers["Size"] ?? 0) > 0 })
    XCTAssertEqual(Set(section.records.map(\.id)).count, section.records.count)
    var regions = [AMRegion](repeating: AMRegion(), count: 1)
    var count: Int32 = 0
    var truncated: Int32 = 0
    XCTAssertEqual(am_process_regions(getpid(), &regions, 1, &count, &truncated), 0)
    XCTAssertEqual(count, 1)
    XCTAssertEqual(truncated, 1)
    var threads = [AMThread](repeating: AMThread(), count: 1)
    XCTAssertEqual(am_process_threads(getpid(), &threads, 1, &count, &truncated), 0)
    XCTAssertEqual(count, 1)
    XCTAssertEqual(truncated, 1)
  }
  func testMemorySnapshotUsesNativeCountersWhenReadable() throws {
    let row = try ownRow()
    let snapshot = DiagnosticCollector.read(identity: ProcessIdentity(row), tab: .memory)
    XCTAssertTrue(snapshot.valid)
    let memory = try XCTUnwrap(snapshot.memory)
    XCTAssertGreaterThan(memory.resident ?? 0, 0)
    XCTAssertGreaterThan(memory.footprint ?? 0, 0)
    XCTAssertTrue(snapshot.fields.contains { $0.name == "Compressed memory" } || memory.compressed == nil)
  }
  func testRateResetsMissingDataAndCounterRollback() {
    XCTAssertEqual(ProcessActivitySample.rate(200, 100, elapsed: 2), 50)
    XCTAssertNil(ProcessActivitySample.rate(100, 200, elapsed: 2))
    XCTAssertNil(ProcessActivitySample.rate(nil, 100, elapsed: 2))
    XCTAssertNil(ProcessActivitySample.rate(100, nil, elapsed: 2))
    XCTAssertNil(ProcessActivitySample.rate(100, 90, elapsed: 0))
    XCTAssertNil(ProcessActivitySample.rate(100, 90, elapsed: 40))
  }
  func testArgumentsExcludeEnvironmentAndPreserveEmptyArguments() {
    var count: Int32 = 3
    var data = withUnsafeBytes(of: &count) { Data($0) }
    data.append(
      Data("/bin/test\0\0/bin/test\0\0argument with spaces\0SECRET=not-an-argument\0".utf8))
    XCTAssertEqual(
      DiagnosticCommand.parseArguments(data), ["/bin/test", "", "argument with spaces"])
    XCTAssertEqual(
      DiagnosticCommand.parseArgumentBuffer(data)?.environment, ["SECRET=not-an-argument"])
    XCTAssertNil(DiagnosticCommand.parseArguments(Data([3, 0, 0, 0, 65])))
  }
  func testCommandTimeoutNonzeroExitAndOutputBound() {
    let start = ProcessInfo.processInfo.systemUptime
    // A child closing its output must still obey the deadline.
    let timed = DiagnosticCommand.run(
      "/bin/sh", ["-c", "exec 1>&- 2>&-; exec /bin/sleep 20"], timeout: 0.2)
    XCTAssertTrue(timed.1.contains("Timed out"), timed.1)
    XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
    let failed = DiagnosticCommand.run("/usr/bin/false", [])
    XCTAssertTrue(failed.1.contains("status 1"))
    let bounded = DiagnosticCommand.run("/usr/bin/yes", ["diagnostic-output"])
    XCTAssertEqual(bounded.0.utf8.count, DiagnosticCommand.outputLimit)
    XCTAssertTrue(bounded.1.contains("limited"))
  }
  func testCommandCancellationStopsWorker() async {
    let worker = Task.detached { DiagnosticCommand.run("/bin/sleep", ["20"]) }
    try? await Task.sleep(for: .milliseconds(50))
    worker.cancel()
    let result = await worker.value
    XCTAssertEqual(result.1, "Cancelled")
  }
  @MainActor func testSessionPauseRetentionAndExitDoNotFollowReusedPID() throws {
    var row = try ownRow()
    let session = ProcessDiagnosticSession(row: row)
    let start = Date()
    session.accept(rows: [row], date: start)
    session.paused = true
    row.cpu = 123
    session.accept(rows: [row], date: start.addingTimeInterval(1))
    XCTAssertEqual(session.histories.count, 1)
    session.paused = false
    for index in 1...1000 {
      session.accept(rows: [row], date: start.addingTimeInterval(Double(index)))
    }
    XCTAssertEqual(session.histories.count, 901)
    XCTAssertEqual(session.histories.last?.cpu, 123)
    let kept = session.row
    row.start += 1
    row.name = "Reused PID"
    session.accept(rows: [row], date: start.addingTimeInterval(1001))
    XCTAssertEqual(session.row, kept)
    XCTAssertFalse(session.exited)  // Original still exists; a partial snapshot is not exit proof.
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/bin/sleep")
    child.arguments = ["30"]
    try child.run()
    var childRow = kept
    childRow.id = child.processIdentifier
    var identity: UInt64 = 0
    XCTAssertEqual(am_process_identity(childRow.id, &identity), 0)
    childRow.start = identity
    let childSession = ProcessDiagnosticSession(row: childRow)
    childSession.accept(rows: [childRow], date: start)
    child.terminate()
    child.waitUntilExit()
    childSession.accept(rows: [], date: start.addingTimeInterval(1))
    XCTAssertTrue(childSession.exited)
    XCTAssertEqual(childSession.histories.count, 1)
  }
  @MainActor func testSessionRecordsMemoryBreakdownAndDeviceGPUHistory() throws {
    var row = try ownRow()
    row.memory = 400
    row.resident = 300
    row.details.privateMemory = 200
    row.details.sharedMemory = 100
    row.details.compressed = 40
    row.details.purgeable = 20
    let session = ProcessDiagnosticSession(row: row)
    let device = GPUDeviceSample(
      id: 1, name: "Test GPU", unifiedMemory: true, memoryUsed: 700, memoryAllocated: 900)
    let date = Date(timeIntervalSince1970: 1)
    session.accept(rows: [row], date: date, gpuDevices: [device])
    XCTAssertEqual(session.memoryHistory.last?.footprint, 400)
    XCTAssertEqual(session.memoryHistory.last?.privateBytes, 200)
    XCTAssertEqual(session.gpuMemoryHistory.last?.used, 700)
    XCTAssertEqual(session.gpuMemoryHistory.last?.allocated, 900)
    XCTAssertEqual(session.gpuMemoryDevices.map(\.id), [1])
    XCTAssertNil(aggregateGPUBytes([UInt64.max, 1]))
    XCTAssertNil(aggregateGPUBytes([nil, nil]))
    XCTAssertNil(aggregateGPUBytes([700, nil]))
    XCTAssertEqual(aggregateGPUBytes([700, 200]), 900)
    for index in 1...1_200 {
      session.accept(
        rows: [row], date: date.addingTimeInterval(Double(index)), gpuDevices: [device])
    }
    XCTAssertEqual(session.memoryHistory.count, 901)
    XCTAssertEqual(session.gpuMemoryHistory.count, 901)
    XCTAssertGreaterThanOrEqual(
      session.memoryHistory.first?.date ?? .distantPast, date.addingTimeInterval(300))
  }
  @MainActor func testSharedLeasesReleaseSessionWithoutRetainingMonitor() async throws {
    let row = try ownRow()
    var monitor: Monitor? = Monitor(startAutomatically: false)
    weak var weakMonitor = monitor
    let center = try XCTUnwrap(monitor).diagnostics
    var first: ProcessDiagnosticSession? = center.acquire(row, details: false)
    weak var weakSession = first
    let second = center.acquire(row, details: false)
    XCTAssertTrue(first === second)
    center.release(second, details: false)
    XCTAssertEqual(center.sessionCount, 1)
    center.release(try XCTUnwrap(first), details: false)
    first = nil
    XCTAssertEqual(center.sessionCount, 0)
    // second is a local strong reference; the center must not keep the Monitor alive.
    XCTAssertNotNil(weakSession)
    weak var released: ProcessDiagnosticSession?
    do {
      let separate = ProcessDiagnosticSession(row: row)
      released = separate
    }
    XCTAssertNil(released)
    monitor = nil
    XCTAssertNil(weakMonitor)
  }
  func testAllSixProcessChartsPreserveMissingSegmentsAndMulticoreValues() {
    let now = Date()
    let history: [ProcessActivitySample] = [
      .init(
        date: now, cpu: 350, memory: 1_000_000, gpu: 240, read: 50, written: 30, received: nil,
        sent: 2, wakeups: 0),
      .init(
        date: now.addingTimeInterval(1), cpu: nil, memory: nil, gpu: nil, read: nil, written: nil,
        received: nil, sent: nil, wakeups: nil),
      .init(
        date: now.addingTimeInterval(2), cpu: 400, memory: 2_000_000, gpu: 260, read: 60,
        written: 40, received: 20, sent: 3, wakeups: 0),
    ]
    for metric in Metric.allCases {
      let samples = ProcessActivityPresentation.samples(history, metric: metric)
      XCTAssertFalse(samples.isEmpty)
      if let first = samples.first, let last = samples.last {
        XCTAssertNotEqual(first.segment, last.segment)
      }
    }
    XCTAssertEqual(
      ProcessActivityPresentation.samples(history, metric: .cpu).map(\.value), [350, 400])
    XCTAssertEqual(
      ProcessActivityPresentation.samples(history, metric: .memory).map(\.value),
      [1_000_000, 2_000_000])
  }
}
