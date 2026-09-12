import Foundation
import XCTest

@testable import ActivityMonitor

final class GPUCollectorTests: XCTestCase {
  func testIntelContextCountersProduceProcessRatesWithoutDoubleCounting() throws {
    func parse(_ ns: UInt64) throws -> GPUClientSample {
      try XCTUnwrap(GPURegistryParser.client(device: 1, id: 2, properties: [
        "IOUserClientCreator": "pid 42, Intel Metal workload",
        "accumulatedGPUTime": ns,
        "AppUsage": [["accumulatedGPUTime": ns]],
      ]))
    }
    var tracker = GPUProcessTracker()
    let initial = try parse(5_000_000_000)
    XCTAssertEqual(initial.nanoseconds, 5_000_000_000)
    _ = tracker.update(snapshot(1, [initial]), identities: [42: 100])
    let result = tracker.update(snapshot(3, [try parse(6_000_000_000)]), identities: [42: 100])
    XCTAssertEqual(result[42]?.percent, 50)
    XCTAssertEqual(result[42]?.seconds, 1)
    let direct = GPURegistryParser.client(device: 1, id: 3, properties: [
      "IOUserClientCreator": "pid 42, Intel", "accumulatedGPUTime": 0,
    ])
    XCTAssertEqual(direct?.nanoseconds, 0)
  }
  func client(_ ns: UInt64, pid: Int32 = 42, device: UInt64 = 1, id: UInt64 = 10, count: Int = 1)
    -> GPUClientSample
  {
    GPUClientSample(
      key: GPUClientKey(device: device, client: id), pid: pid, nanoseconds: ns, counterCount: count)
  }
  func snapshot(_ time: Double, _ clients: [GPUClientSample]) -> GPUHardwareSnapshot {
    GPUHardwareSnapshot(devices: [], clients: clients, uptime: time)
  }
  func testParserDistinguishesZeroFromMissingAndRejectsInvalidNumbers() {
    XCTAssertEqual(GPURegistryParser.percent(0), 0)
    XCTAssertEqual(GPURegistryParser.percent(100), 100)
    for invalid: Any in [true, -1, 101, Double.nan, Double.infinity, "20"] {
      XCTAssertNil(GPURegistryParser.percent(invalid))
    }
    XCTAssertNil(GPURegistryParser.percent(nil))
    XCTAssertEqual(GPURegistryParser.unsigned(NSNumber(value: UInt64.max)), UInt64.max)
    for invalid: Any in [true, -1, 1.5, Double.infinity, "30"] {
      XCTAssertNil(GPURegistryParser.unsigned(invalid))
    }
    let partial = GPURegistryParser.device(
      id: 1, name: "Test GPU", unified: true,
      properties: [
        "PerformanceStatistics": [
          "Device Utilization %": 0, "Tiler Utilization %": true,
          "In use system memory": UInt64(123),
        ]
      ])
    XCTAssertEqual(partial.utilization, 0)
    XCTAssertNil(partial.renderer)
    XCTAssertNil(partial.tiler)
    XCTAssertEqual(partial.memoryUsed, 123)
    XCTAssertNil(partial.memoryAllocated)
  }
  func testClientParsingRejectsMalformedAndOverflowingCounters() throws {
    func parse(_ creator: String, _ usage: Any) -> GPUClientSample? {
      GPURegistryParser.client(
        device: 1, id: 2, properties: ["IOUserClientCreator": creator, "AppUsage": usage])
    }
    let parsed = try XCTUnwrap(
      parse("pid 42, Test, app", [["accumulatedGPUTime": 123], ["accumulatedGPUTime": 456]]))
    XCTAssertEqual(parsed.pid, 42)
    XCTAssertEqual(parsed.nanoseconds, 579)
    XCTAssertEqual(parsed.counterCount, 2)
    XCTAssertNil(parse("not pid 42", [["accumulatedGPUTime": 1]]))
    XCTAssertNil(parse("pid -1, app", [["accumulatedGPUTime": 1]]))
    XCTAssertNil(parse("pid 42, app", []))
    XCTAssertNil(parse("pid 42, app", [["accumulatedGPUTime": true]]))
    XCTAssertNil(
      parse("pid 42, app", [["accumulatedGPUTime": UInt64.max], ["accumulatedGPUTime": 1]]))
    XCTAssertNil(parse("pid 42, app", [["accumulatedGPUTime": 1], ["other": 2]]))
  }
  func testAlternateDriverAndMetalParentIdentity() {
    let device = GPURegistryParser.device(
      id: 1, name: "Discrete GPU", unified: false,
      properties: ["PerformanceStatistics": ["GPU Activity(%)": 42]])
    XCTAssertEqual(device.utilization, 42)
    XCTAssertNil(device.memoryUsed)
    XCTAssertEqual(
      GPURegistryParser.metalID(accelerator: 1, ancestors: [2, 3], metalIDs: [1, 2]), 1)
    XCTAssertEqual(GPURegistryParser.metalID(accelerator: 1, ancestors: [2, 3], metalIDs: [2]), 2)
    XCTAssertNil(GPURegistryParser.metalID(accelerator: 1, ancestors: [2, 3], metalIDs: [4]))
  }
  func testIndividualCounterResetCannotBeMaskedByAnotherGrowingCounter() {
    var tracker = GPUProcessTracker()
    var a = client(100, count: 2)
    a.counters = [100, 0]
    var b = client(200, count: 2)
    b.counters = [0, 200]
    _ = tracker.update(snapshot(1, [a]), identities: [42: 100])
    XCTAssertNil(tracker.update(snapshot(2, [b]), identities: [42: 100])[42]?.percent)
  }
  func testRatesWarmupZeroNanosecondsAndOverlappingWork() throws {
    var tracker = GPUProcessTracker()
    let ids: [Int32: UInt64] = [42: 100]
    let initial = tracker.update(snapshot(10, [client(9_000_000_000)]), identities: ids)[42]
    XCTAssertNil(initial?.percent)
    XCTAssertNil(initial?.seconds)
    XCTAssertEqual(initial?.waiting, true)
    let zero = tracker.update(snapshot(12, [client(9_000_000_000)]), identities: ids)[42]
    XCTAssertEqual(zero?.percent, 0)
    XCTAssertEqual(zero?.seconds, 0)
    let active = tracker.update(snapshot(14, [client(14_000_000_000)]), identities: ids)[42]
    XCTAssertEqual(active?.percent, 250)
    XCTAssertEqual(active?.seconds, 5)
  }
  func testCounterResetsQueueChangesAndPIDReuseRebaseline() {
    var tracker = GPUProcessTracker()
    var ids: [Int32: UInt64] = [42: 100]
    _ = tracker.update(snapshot(1, [client(1_000)]), identities: ids)
    XCTAssertNil(tracker.update(snapshot(2, [client(0)]), identities: ids)[42]?.percent)
    XCTAssertNil(
      tracker.update(snapshot(3, [client(4_000, count: 2)]), identities: ids)[42]?.percent)
    XCTAssertEqual(
      tracker.update(snapshot(4, [client(5_000, count: 2)]), identities: ids)[42]?.seconds, 0.000001
    )
    ids[42] = 101
    let reused = tracker.update(snapshot(5, [client(6_000, count: 2)]), identities: ids)[42]
    XCTAssertNil(reused?.percent)
    XCTAssertNil(reused?.seconds)
    XCTAssertTrue(tracker.update(snapshot(6, []), identities: [:]).isEmpty)
  }
  func testMultipleDevicesDeduplicationAndRemovedClients() {
    var tracker = GPUProcessTracker()
    let ids: [Int32: UInt64] = [42: 100]
    _ = tracker.update(snapshot(1, [client(0), client(0, device: 2)]), identities: ids)
    let a = client(1_000_000_000)
    let b = client(2_000_000_000, device: 2)
    let result = tracker.update(snapshot(3, [a, a, b]), identities: ids)[42]
    XCTAssertEqual(result?.percent, 150)
    XCTAssertEqual(result?.seconds, 3)
    let missing = tracker.update(snapshot(4, []), identities: ids)[42]
    XCTAssertNil(missing?.percent)
    XCTAssertEqual(missing?.seconds, 3)
    XCTAssertNil(tracker.update(snapshot(5, [a]), identities: ids)[42]?.percent)
  }
  func testInvalidMonotonicIntervalRebaselines() {
    var tracker = GPUProcessTracker()
    let ids: [Int32: UInt64] = [42: 100]
    _ = tracker.update(snapshot(1, [client(0)]), identities: ids)
    XCTAssertNil(tracker.update(snapshot(1, [client(1_000)]), identities: ids)[42]?.percent)
    XCTAssertNil(tracker.update(snapshot(0, [client(2_000)]), identities: ids)[42]?.percent)
    XCTAssertEqual(
      tracker.update(snapshot(1, [client(3_000)]), identities: ids)[42]?.seconds, 0.000001)
  }
  @MainActor func testDevicesDisconnectReconnectAndRetainSeparateBoundedHistories() {
    let monitor = Monitor(startAutomatically: false)
    let first = GPUDeviceSample(id: 1, name: "First", unifiedMemory: true, utilization: 30)
    let second = GPUDeviceSample(id: 2, name: "Second", unifiedMemory: false, utilization: 0)
    let date = Date(timeIntervalSince1970: 0)
    monitor.updateGPU([first, second], date: date)
    monitor.selectedGPU = 2
    monitor.updateGPU([first], date: date.addingTimeInterval(2))
    XCTAssertEqual(monitor.gpuDevice?.name, "Second")
    XCTAssertEqual(monitor.gpuDevice?.connected, false)
    XCTAssertNil(monitor.gpuDevice?.utilization)
    XCTAssertEqual(monitor.gpuHistories[1]?.last?.utilization, 30)
    XCTAssertNil(monitor.gpuHistories[2]?.last?.utilization)
    monitor.updateGPU([first, second], date: date.addingTimeInterval(1000))
    XCTAssertEqual(monitor.gpuDevice?.connected, true)
    XCTAssertEqual(monitor.gpuHistories[2]?.count, 1)
    XCTAssertEqual(monitor.gpuHistories[2]?.last?.utilization, 0)
  }
  func testHistorySplitsMissingAndLongGapsAndPreservesZero() {
    let points = [(0.0, 10.0 as Double?), (2, 0), (4, nil), (6, 20), (100, 30)].map {
      GPUHistoryPoint(date: Date(timeIntervalSince1970: $0.0), utilization: $0.1)
    }
    let segments = gpuHistorySegments(points, maximumGap: 10)
    XCTAssertEqual(segments.map(\.count), [2, 1, 1])
    XCTAssertEqual(segments[0].last?.utilization, 0)
  }
  func testGPUSortKeepsUnavailableLastInEitherDirectionAndExportsMeasuredZero() throws {
    var a = ProcessRow(
      id: 42, parent: 1, uid: 1, start: 1, name: "Test", user: "User", cpu: 0, cpuTime: 0,
      memory: 0, resident: 0, threads: 0, read: 0, written: 0, isApp: false, accessible: false,
      kind: "Apple", ioAccessible: false)
    var b = a
    b.id = 43
    b.gpuPercent = 0
    b.gpuTime = 0
    var c = a
    c.id = 44
    c.gpuPercent = 200
    c.gpuTime = 2
    for key in ["primary", "gpu", "gpuTime"] {
      var query = ProcessQuery(
        metric: .gpu, query: "", filter: "All processes", sort: key, descending: true)
      XCTAssertEqual(query.apply([a, b, c]).map(\.id), [44, 43, 42])
      query.descending = false
      XCTAssertEqual(query.apply([c, a, b]).map(\.id), [43, 44, 42])
    }
    XCTAssertTrue(processCSV([a]).hasSuffix(",,"))
    XCTAssertTrue(processCSV([b]).hasSuffix(",0.0000,0.0"))
    let data = try JSONEncoder().encode([a, b, c])
    XCTAssertEqual(try JSONDecoder().decode([ProcessRow].self, from: data), [a, b, c])
    let gpu = GPUExportSnapshot(
      capturedAt: Date(timeIntervalSince1970: 0), selectedDevice: 1,
      devices: [GPUDeviceSample(id: 1, name: "Test", unifiedMemory: true, utilization: 0)],
      history: ["1": [GPUHistoryPoint(date: Date(timeIntervalSince1970: 0), utilization: nil)]],
      processes: [b])
    let export = try JSONEncoder().encode(gpu)
    let decoded = try JSONDecoder().decode(GPUExportSnapshot.self, from: export)
    XCTAssertEqual(decoded.devices[0].utilization, 0)
    XCTAssertNil(decoded.history["1"]?[0].utilization)
    XCTAssertEqual(decoded.processes[0].gpuPercent, 0)
    a.gpuWaiting = true
    XCTAssertEqual(a.gpuAvailability, "Waiting for a second GPU sample")
    XCTAssertEqual(gpuDuration(3661.25), "1:01:01.25")
    XCTAssertEqual(gpuDuration(nil), "—")
    XCTAssertEqual(gpuDuration(59.999), "0:01:00.00")
    XCTAssertEqual(gpuDuration(3599.999), "1:00:00.00")
  }
}
