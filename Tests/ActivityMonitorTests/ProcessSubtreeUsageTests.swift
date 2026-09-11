import SystemBridge
import XCTest

@testable import ActivityMonitor

enum ProcessUsageFixture {
  static func row(_ id: Int32, parent: Int32 = -1, units: UInt64) -> ProcessRow {
    var row = ProcessTreeFixture.row(id, parent: parent)
    row.cpu = Double(units) * 10.25
    row.cpuTime = Double(units) * 2
    row.gpuPercent = Double(units) * 5
    row.gpuTime = Double(units) * 0.125
    row.threads = UInt32(units * 2)
    row.memory = units * 1024
    row.resident = units * 2048
    row.read = units * 17
    row.written = units * 19
    row.networkReceived = units * 23
    row.networkSent = units * 29
    row.ioAccessible = true
    row.cpuSampleAvailable = true
    row.memoryUsesResidentFallback = false
    row.details = ProcessDetails(
      ports: units * 41, privateMemory: units * 43, sharedMemory: units * 47,
      purgeable: units * 53, compressed: units * 59, wakeups: Double(units) * 0.25,
      packetsIn: units * 31, packetsOut: units * 37,
      sandbox: true, restricted: false, preventingSleep: false)
    return row
  }

  static var rows: [ProcessRow] {
    [
      row(10, units: 1), row(20, parent: 10, units: 2), row(30, parent: 20, units: 3),
      row(50, parent: 10, units: 5), row(60, units: 11),
    ]
  }

  static func unavailable(_ row: ProcessRow) -> ProcessRow {
    var row = row
    row.accessible = false
    row.ioAccessible = false
    row.gpuPercent = nil
    row.gpuTime = nil
    row.networkReceived = nil
    row.networkSent = nil
    row.details = ProcessDetails()
    return row
  }
}

final class ProcessSubtreeUsageTests: XCTestCase {
  func testEveryAdditiveMetricIncludesOwnChildrenAndGrandchildrenOnce() throws {
    let rows = ProcessUsageFixture.rows
    let tree = ProcessTreeSnapshot.build(rows, query: ProcessTreeFixture.query())
    let total = try XCTUnwrap(tree.usageByID[10])
    // Independently calculated from units 1 + 2 + 3 + 5, not from displayed parent totals.
    let expected: [ProcessUsageMetric: ProcessSortValue] = [
      .cpu: .number(112.75), .time: .number(22), .gpu: .number(55), .gpuTime: .number(1.375),
      .threads: .integer(22), .memory: .integer(11264), .resident: .integer(22528),
      .read: .integer(187), .written: .integer(209), .received: .integer(253), .sent: .integer(319),
      .packetsIn: .integer(341), .packetsOut: .integer(407), .ports: .integer(451),
      .privateMemory: .integer(473), .sharedMemory: .integer(517), .purgeable: .integer(583),
      .compressed: .integer(649), .wakeups: .number(2.75),
    ]
    XCTAssertEqual(Set(expected.keys), Set(ProcessUsageMetric.allCases))
    XCTAssertEqual(total.processCount, 4)
    for (metric, value) in expected {
      XCTAssertEqual(total[metric].value, value, metric.rawValue)
      XCTAssertEqual(total[metric].reportedProcesses, 4)
      XCTAssertFalse(total[metric].isPartial(processCount: 4))
    }
    XCTAssertEqual(tree.usageByID[20]?.processCount, 2)
    XCTAssertEqual(tree.usageByID[20]?[.cpu].value, .number(51.25))
    XCTAssertEqual(tree.usageByID[30]?.processCount, 1)
    XCTAssertEqual(tree.usageByID[60]?.processCount, 1)
    XCTAssertEqual(tree.rowsByID[10], rows[0], "Actions must retain the original process record")
    XCTAssertEqual(tree.entries.first?.row.cpu, 10.25)
    XCTAssertEqual(ProcessValues.value(rows[0], key: "cpu", metric: .cpu), .number(10.25))
    XCTAssertEqual(
      ProcessValues.value(rows[0], key: "primary", metric: .cpu, usage: total), .number(112.75))
    XCTAssertEqual(
      ProcessValues.value(rows[0], key: "pid", metric: .cpu, usage: total), .integer(10))
    XCTAssertEqual(
      ProcessValues.value(rows[0], key: "sandbox", metric: .cpu, usage: total), .integer(1))
    XCTAssertNil(ProcessValues.value(rows[0], key: "energyImpact", metric: .energy, usage: total))
  }

  func testMissingCountersProducePartialSubtotalsAndNeverInventZero() throws {
    let parent = ProcessUsageFixture.unavailable(ProcessUsageFixture.row(10, units: 100))
    let child = ProcessUsageFixture.row(20, parent: 10, units: 2)
    let grandchild = ProcessUsageFixture.unavailable(
      ProcessUsageFixture.row(30, parent: 20, units: 100))
    let tree = ProcessTreeSnapshot(sortedRows: [parent, child, grandchild])
    let total = try XCTUnwrap(tree.usageByID[10])
    XCTAssertEqual(total.processCount, 3)
    for metric in ProcessUsageMetric.allCases {
      XCTAssertEqual(
        total[metric].value, ProcessValues.value(child, key: metric.rawValue, metric: .cpu))
      XCTAssertEqual(total[metric].reportedProcesses, 1)
      XCTAssertTrue(
        ProcessValues.text(parent, key: metric.rawValue, metric: .cpu, usage: total).hasPrefix("≥"))
    }
    XCTAssertEqual(ProcessValues.text(parent, key: "cpu", metric: .cpu, usage: total), "≥20.5")
    let unknown = ProcessSubtreeUsage(parent)
    for metric in ProcessUsageMetric.allCases {
      XCTAssertNil(unknown[metric].value)
      XCTAssertEqual(unknown[metric].reportedProcesses, 0)
      XCTAssertEqual(
        ProcessValues.text(parent, key: metric.rawValue, metric: .cpu, usage: unknown), "—")
    }
    let zero = ProcessUsageFixture.row(40, parent: 10, units: 0)
    let partialZero = try XCTUnwrap(ProcessTreeSnapshot(sortedRows: [parent, zero]).usageByID[10])
    XCTAssertEqual(ProcessValues.text(parent, key: "cpu", metric: .cpu, usage: partialZero), "≥0.0")
    XCTAssertEqual(
      ProcessValues.text(zero, key: "cpu", metric: .cpu, usage: ProcessSubtreeUsage(zero)), "0.0")
  }

  func testWarmupResetAndInvalidRatesAreMissingWhileValidIdleIsZero() throws {
    var before = AMProcess()
    before.pid = 10
    before.start = 100
    before.accessible = 1
    before.cpu = 2_000_000_000
    XCTAssertNil(CPUAccounting.sampledProcessPercent(current: before, previous: nil, elapsed: 1))
    XCTAssertEqual(
      CPUAccounting.sampledProcessPercent(current: before, previous: before, elapsed: 1), 0)
    var current = before
    current.cpu = 1
    XCTAssertNil(
      CPUAccounting.sampledProcessPercent(current: current, previous: before, elapsed: 1))
    current.cpu = 9_000_000_000
    current.start = 101
    XCTAssertNil(
      CPUAccounting.sampledProcessPercent(current: current, previous: before, elapsed: 1))
    current.start = 100
    XCTAssertEqual(
      CPUAccounting.sampledProcessPercent(current: current, previous: before, elapsed: 2), 350)

    var row = ProcessUsageFixture.row(10, units: 1)
    row.cpuSampleAvailable = false
    XCTAssertNil(ProcessSubtreeUsage(row)[.cpu].value)
    XCTAssertEqual(ProcessSubtreeUsage(row)[.time].value, .number(2))
    XCTAssertEqual(ProcessValues.text(row, key: "cpu", metric: .cpu), "—")
    row.cpu = 0
    XCTAssertFalse(ProcessTreeFixture.query(filter: "Inactive processes").matches(row))
    row.cpuSampleAvailable = true
    XCTAssertTrue(ProcessTreeFixture.query(filter: "Inactive processes").matches(row))
    for invalid in [Double.nan, .infinity, -.infinity, -1] {
      row.cpu = invalid
      row.gpuPercent = invalid
      row.details.wakeups = invalid
      let usage = ProcessSubtreeUsage(row)
      XCTAssertNil(usage[.cpu].value)
      XCTAssertNil(usage[.gpu].value)
      XCTAssertNil(usage[.wakeups].value)
    }
  }

  func testIntegerPrecisionAndOverflowArePreservedAndMarked() throws {
    var parent = ProcessUsageFixture.row(10, units: 0)
    var child = ProcessUsageFixture.row(20, parent: 10, units: 0)
    parent.read = 9_007_199_254_740_993
    child.read = 2
    parent.written = .max
    child.written = 1
    parent.cpu = .greatestFiniteMagnitude
    child.cpu = .greatestFiniteMagnitude
    parent.cpuTime = .greatestFiniteMagnitude
    child.cpuTime = .greatestFiniteMagnitude
    let total = try XCTUnwrap(ProcessTreeSnapshot(sortedRows: [parent, child]).usageByID[10])
    XCTAssertEqual(total[.read].value, .integer(9_007_199_254_740_995))
    XCTAssertFalse(total[.read].overflowed)
    XCTAssertEqual(total[.written].value, .integer(.max))
    XCTAssertTrue(total[.written].overflowed)
    XCTAssertEqual(total[.written].reportedProcesses, 2)
    XCTAssertTrue(
      ProcessValues.text(parent, key: "written", metric: .disk, usage: total).hasPrefix("≥"))
    XCTAssertEqual(total[.cpu].value, .number(.greatestFiniteMagnitude))
    XCTAssertTrue(total[.cpu].overflowed)
    XCTAssertTrue(
      ProcessValues.text(parent, key: "time", metric: .cpu, usage: total).hasPrefix("≥"))
  }

  func testFilterAndCollapseDoNotChangeTheSubtreeBeingMeasured() throws {
    let rows = ProcessUsageFixture.rows
    let state = ProcessTreePresentation()
    state.update(rows, query: ProcessTreeFixture.query())
    let total = try XCTUnwrap(state.snapshot.usageByID[10])
    state.setExpanded(10, false, recursive: true)
    XCTAssertEqual(state.entries.map(\.id), [10, 60])
    XCTAssertEqual(state.entries[0].usage, total)
    state.update(rows, query: ProcessTreeFixture.query("Process 30"))
    XCTAssertEqual(state.entries.map(\.id), [10, 20, 30])
    XCTAssertEqual(state.entries[0].usage, total)
    state.update(rows, query: ProcessTreeFixture.query("Process 10"))
    XCTAssertEqual(state.entries.map(\.id), [10])
    XCTAssertFalse(state.entries[0].hasChildren)
    XCTAssertEqual(state.entries[0].usage?.processCount, 4)
    XCTAssertEqual(state.entries[0].usage, total)
  }

  func testMembershipChangesAndReusedParentsNeverRetainOldUsage() throws {
    var rows = Array(ProcessUsageFixture.rows.prefix(3))
    func total(_ id: Int32) -> ProcessSubtreeUsage? {
      ProcessTreeSnapshot(sortedRows: rows).usageByID[id]
    }
    XCTAssertEqual(total(10)?[.cpu].value, .number(61.5))
    rows[2].parent = -1
    XCTAssertEqual(total(10)?[.cpu].value, .number(30.75))
    rows[2].parent = 20
    rows[1].start = 200
    XCTAssertEqual(total(10)?.processCount, 2, "The old child cannot attach to a recycled parent")
    rows[2].start = 201
    XCTAssertEqual(total(10)?.processCount, 3)
    rows.removeLast()
    XCTAssertEqual(total(10)?[.cpu].value, .number(30.75))
    rows[1].cpu = 400
    XCTAssertEqual(
      total(10)?[.cpu].value, .number(410.25), "Rates are summed after per-identity sampling")
  }

  func testCyclesDuplicateRowsAndMissingParentsCountEachIdentityOnce() throws {
    var rows = Array(ProcessUsageFixture.rows.prefix(3))
    rows[0].parent = 30
    let tree = ProcessTreeSnapshot(sortedRows: rows + rows)
    XCTAssertEqual(tree.parents, [20: 10, 30: 20])
    XCTAssertEqual(tree.usageByID[10]?.processCount, 3)
    XCTAssertEqual(tree.usageByID[10]?[.cpu].value, .number(61.5))
    rows[1].parent = 999
    let orphan = ProcessTreeSnapshot(sortedRows: rows)
    XCTAssertEqual(orphan.usageByID[20]?.processCount, 3)
    XCTAssertEqual(orphan.usageByID[20]?[.cpu].value, .number(61.5))
  }

  func testMemoryFallbackIsReportedAndDoesNotPretendToDeduplicateSharedPages() throws {
    var rows = Array(ProcessUsageFixture.rows.prefix(2))
    rows[1].memory = rows[1].resident
    rows[1].memoryUsesResidentFallback = true
    let total = try XCTUnwrap(ProcessTreeSnapshot(sortedRows: rows).usageByID[10])
    XCTAssertEqual(total[.memory].value, .integer(5120))
    XCTAssertEqual(total.residentFallbackCount, 1)
    XCTAssertEqual(total[.sharedMemory].value, .integer(141))
    XCTAssertTrue(total.coverage(.memory).contains("1 use resident memory fallback"))
    XCTAssertTrue(ProcessUsageMetric.sharedMemory.help.contains("not unique physical RAM"))
  }

  func testCopyAndExportsUseDisplayedTotalsAndRetainOwnProcessRecords() throws {
    let tree = ProcessTreeSnapshot.build(
      ProcessUsageFixture.rows, query: ProcessTreeFixture.query("Process 30"))
    let rows = tree.entries.map(\.row)
    let copied = processClipboard(
      rows, keys: ["pid", "primary", "name"], metric: .cpu, usage: tree.usageByID)
    XCTAssertEqual(
      copied.components(separatedBy: "\n"),
      [
        "PID\tΣ % CPU\tProcess name", "10\t112.8\tProcess 10", "20\t51.2\tProcess 20",
        "30\t30.8\tProcess 30",
      ])
    let own = processClipboard(rows, keys: ["pid", "primary"], metric: .cpu)
    XCTAssertTrue(own.contains("10\t10.2"))
    XCTAssertFalse(own.contains("Σ"))
    let csv = processCSV(rows, usage: tree.usageByID).components(separatedBy: "\n")
    let fields = csv[0].components(separatedBy: ",")
    let first = Dictionary(uniqueKeysWithValues: zip(fields, csv[1].components(separatedBy: ",")))
    XCTAssertEqual(first["CPU %"], "10.25")
    XCTAssertEqual(first["Parent PID"], "-1")
    XCTAssertEqual(first["Subtree CPU %"], "112.75")
    XCTAssertEqual(first["Subtree processes"], "4", "Filtered-out descendants still contribute")
    XCTAssertEqual(first["Subtree CPU % reporting processes"], "4")
    XCTAssertEqual(first["Subtree CPU % status"], "complete")
    XCTAssertEqual(csv.count, 4)
    XCTAssertFalse(processCSV(rows).contains("Subtree"))

    let data = try processJSON(rows, usage: tree.usageByID)
    let decoded = try JSONDecoder().decode(ProcessTreeExportSnapshot.self, from: data)
    XCTAssertEqual(decoded.scope, "process-and-current-descendants")
    XCTAssertEqual(decoded.rows.map(\.process), rows)
    XCTAssertEqual(decoded.rows.first?.subtree?.processCount, 4)
    XCTAssertEqual(decoded.rows.first?.subtree?.counters["cpu"]?.value?.csvValue, "112.75")
    XCTAssertEqual(try JSONDecoder().decode([ProcessRow].self, from: processJSON(rows)), rows)
    let gpu = GPUExportSnapshot(
      capturedAt: nil, selectedDevice: nil, devices: [], history: [:], processes: rows,
      subtreeUsage: ["10": ProcessUsageExport(tree.usageByID[10]!)],
      subtreeScope: ProcessSubtreeUsage.scopeHelp)
    let gpuRoundTrip = try JSONDecoder().decode(
      GPUExportSnapshot.self, from: JSONEncoder().encode(gpu))
    XCTAssertEqual(gpuRoundTrip.processes, rows)
    XCTAssertEqual(gpuRoundTrip.subtreeUsage?["10"]?.counters["gpu"]?.value?.csvValue, "55")
  }

  func testExportSeparatesPartialZeroUnavailableAndOverflowFromCompleteValues() throws {
    var parent = ProcessUsageFixture.row(10, units: 1)
    var child = ProcessUsageFixture.row(20, parent: 10, units: 0)
    parent.cpuSampleAvailable = false
    parent.gpuPercent = nil
    child.gpuPercent = nil
    parent.written = .max
    child.written = 1
    let tree = ProcessTreeSnapshot(sortedRows: [parent, child])
    let data = try processJSON([parent], usage: tree.usageByID)
    XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("18446744073709551615"))
    let exported = try JSONDecoder().decode(ProcessTreeExportSnapshot.self, from: data)
    let counters = try XCTUnwrap(exported.rows.first?.subtree?.counters)
    XCTAssertEqual(counters["cpu"]?.value?.csvValue, "0")
    XCTAssertEqual(counters["cpu"]?.reportedProcesses, 1)
    XCTAssertEqual(counters["cpu"]?.status, "partial")
    XCTAssertEqual(counters["gpu"]?.reportedProcesses, 0)
    XCTAssertEqual(counters["gpu"]?.status, "unavailable")
    XCTAssertNil(counters["gpu"]?.value)
    XCTAssertEqual(counters["written"]?.value?.csvValue, "18446744073709551615")
    XCTAssertEqual(counters["written"]?.status, "overflow")
    let csv = processCSV([parent], usage: tree.usageByID).components(separatedBy: "\n")
    let first = Dictionary(
      uniqueKeysWithValues: zip(
        csv[0].components(separatedBy: ","), csv[1].components(separatedBy: ",")))
    XCTAssertEqual(first["CPU %"], "", "An unsampled own CPU rate must remain unavailable")
    XCTAssertEqual(first["Subtree CPU %"], "0.0")
    XCTAssertEqual(first["Subtree CPU % status"], "partial")
    XCTAssertEqual(first["Subtree GPU %"], "")
    XCTAssertEqual(first["Subtree GPU % status"], "unavailable")
    XCTAssertEqual(first["Subtree Bytes written"], "18446744073709551615")
    XCTAssertEqual(first["Subtree Bytes written status"], "overflow")
  }
}
