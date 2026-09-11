import AppKit
import XCTest

@testable import ActivityMonitor

final class ProcessListInteractionsTests: XCTestCase {
  func testNarrowNumericCellsMarkTruncationInsteadOfClippingLeadingDigits() {
    let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    let value = ProcessCellText.truncate("123456789 GB", width: 40, font: font)
    XCTAssertTrue(value.hasPrefix("123"))
    XCTAssertTrue(value.hasSuffix("…"))
    XCTAssertLessThanOrEqual((value as NSString).size(withAttributes: [.font: font]).width, 40)
    XCTAssertEqual(ProcessCellText.truncate("12 GB", width: 100, font: font), "12 GB")
  }
  func testColumnWidthsPersistPerViewClampAndReset() {
    var widths = ProcessColumnWidths()
    widths.set("name", metric: .cpu, width: 410)
    widths.set("primary", metric: .memory, width: 170)
    widths.set("pid", metric: .cpu, width: -20)
    widths = ProcessColumnWidths(widths.json)
    XCTAssertEqual(widths.width("name", metric: .cpu), 410)
    XCTAssertEqual(widths.width("pid", metric: .cpu), 60)
    XCTAssertNil(widths.width("name", metric: .memory))
    widths.reset(.cpu)
    XCTAssertNil(widths.width("name", metric: .cpu))
    XCTAssertEqual(widths.width("primary", metric: .memory), 170)
    XCTAssertNil(ProcessColumnWidths("invalid").width("pid", metric: .cpu))
    XCTAssertEqual(ProcessColumnWidths.clamp(.infinity, key: "name"), 140)
  }
  func testDefaultSizingUsesCompactMetricsAndFillsActualViewport() {
    let columns = ProcessColumns.defaults(.cpu)
    let layout = ProcessColumnLayout(viewport: 1377, metric: .cpu, columns: columns, saved: .init())
    XCTAssertEqual(layout.total, 1377)
    XCTAssertEqual(layout.width("pid"), 64)
    XCTAssertEqual(layout.name + layout.widths.values.reduce(0, +), layout.total)
    let small = ProcessColumnLayout(viewport: 360, metric: .cpu, columns: columns, saved: .init())
    XCTAssertEqual(small.name, 180)
    XCTAssertGreaterThan(small.total, 360)
    var saved = ProcessColumnWidths()
    saved.set("primary", metric: .cpu, width: 180)
    let changed = ProcessColumnLayout(viewport: 1377, metric: .cpu, columns: columns, saved: saved)
    XCTAssertEqual(changed.width("primary"), 180)
    XCTAssertEqual(changed.width("pid"), layout.width("pid"))
    XCTAssertEqual(changed.total, 1377)
  }
  func testDividerResizeKeepsNeighborWidthsAndMovesTheDivider() {
    let columns = ProcessColumns.defaults(.cpu)
    var saved = ProcessColumnWidths()
    let before = ProcessColumnLayout(viewport: 1377, metric: .cpu, columns: columns, saved: saved)
    saved.resize(
      "primary", metric: .cpu, columns: columns, viewport: 1377, to: before.width("primary") + 70)
    let after = ProcessColumnLayout(viewport: 1377, metric: .cpu, columns: columns, saved: saved)
    XCTAssertEqual(after.name, before.name)
    XCTAssertEqual(after.offset("time"), before.offset("time") + 70)
    XCTAssertEqual(after.total, before.total + 70)
    let all = ProcessColumnLayout(
      viewport: 1377, metric: .cpu, columns: ProcessColumns.available(.cpu), saved: .init())
    XCTAssertEqual(all.name, 240)
  }
  func testReorderingIncludesNameAndSurvivesHiddenColumnsAndRelaunch() {
    var order = ProcessColumnOrder()
    order.move("name", to: "threads", metric: .cpu)
    order = ProcessColumnOrder(order.json)
    XCTAssertEqual(
      order.ordered(["name", "primary", "time", "threads", "pid"], metric: .cpu),
      ["primary", "time", "threads", "name", "pid"])
    XCTAssertEqual(
      order.ordered(["name", "primary", "pid"], metric: .cpu), ["primary", "name", "pid"])
    XCTAssertEqual(
      order.ordered(["name", "primary", "pid"], metric: .memory), ["name", "primary", "pid"])
    let layout = ProcessColumnLayout(
      viewport: 1200, metric: .cpu, columns: ProcessColumns.defaults(.cpu), saved: .init(),
      order: order)
    XCTAssertEqual(
      layout.offset("name"),
      layout.width("primary") + layout.width("time") + layout.width("threads"))
    order.reset(.cpu)
    XCTAssertEqual(order.ordered(["name", "primary"], metric: .cpu), ["name", "primary"])
    XCTAssertEqual(
      ProcessColumnOrder("{\"CPU\":[\"name\",\"name\",\"bad\"]}").ordered(
        ["name", "pid"], metric: .cpu), ["name", "pid"])
  }
  func testRangeSelectionToggleAndKeyboardExtension() {
    let rows: [Int32] = [10, 20, 30, 40, 50]
    var selection = ProcessListSelection()
    selection.select(20, order: rows)
    selection.select(40, order: rows, extending: true)
    XCTAssertEqual(selection.ids, [20, 30, 40])
    selection.move(-1, order: rows, extending: true)
    XCTAssertEqual(selection.ids, [20, 30])
    selection.select(50, order: rows, toggling: true)
    XCTAssertEqual(selection.ids, [20, 30, 50])
    selection.select(30, order: rows, toggling: true)
    XCTAssertEqual(selection.ids, [20, 50])
    selection.move(-100, order: rows)
    XCTAssertEqual(selection.ids, [10])
    selection.move(100, order: rows)
    XCTAssertEqual(selection.ids, [50])
  }
  func testClipboardUsesDisplayedColumnOrderAndSanitizesNames() throws {
    var row = try XCTUnwrap(Collector().collect().processes.first { $0.id == getpid() })
    row.id = 42
    row.name = "Example\tVM\nName"
    let text = processClipboard([row], keys: ["pid", "name", "ports"], metric: .cpu)
    XCTAssertEqual(text, "PID\tProcess name\tPorts\n42\tExample VM Name\t—")
  }
  func testHierarchyKeepsSiblingSortCollapsesBranchesAndHandlesCycles() throws {
    let template = try XCTUnwrap(Collector().collect().processes.first { $0.id == getpid() })
    func row(_ id: Int32, _ parent: Int32) -> ProcessRow {
      var row = template
      row.id = id
      row.parent = parent
      return row
    }
    let rows = [row(3, 1), row(2, 1), row(1, 0), row(5, 6), row(6, 5), row(4, 2)]
    let expanded = ProcessTreeSnapshot(sortedRows: rows).visible(collapsed: [])
    XCTAssertEqual(expanded.map(\.id), [1, 3, 2, 4, 5, 6])
    XCTAssertEqual(expanded.map(\.depth), [0, 1, 1, 2, 0, 1])
    XCTAssertEqual(
      ProcessTreeSnapshot(sortedRows: rows).visible(collapsed: [ProcessIdentity(rows[2])]).map(
        \.id), [1, 5, 6])
    XCTAssertEqual(
      ProcessTreeSnapshot(sortedRows: rows).visible(collapsed: [ProcessIdentity(rows[1])]).map(
        \.id), [1, 3, 2, 5, 6])
  }
  func testAdditionalFiltersUseKnownSamplesAndSelectedSnapshot() throws {
    var row = try XCTUnwrap(Collector().collect().processes.first { $0.id == getpid() })
    row.cpu = 2
    row.cpuSampleAvailable = true
    row.accessible = true
    row.gpuPercent = 5
    func query(_ filter: String) -> ProcessQuery {
      ProcessQuery(
        metric: .cpu, query: "", filter: filter, sort: "name", descending: false, selected: [row.id]
      )
    }
    XCTAssertTrue(query("Active processes").matchesFilter(row))
    XCTAssertFalse(query("Inactive processes").matchesFilter(row))
    XCTAssertTrue(query("GPU processes").matchesFilter(row))
    XCTAssertTrue(query("Selected processes").matchesFilter(row))
    row.accessible = false
    XCTAssertFalse(query("Active processes").matchesFilter(row))
    XCTAssertFalse(query("Inactive processes").matchesFilter(row))
    row.gpuPercent = nil
    XCTAssertFalse(query("GPU processes").matchesFilter(row))
  }
}
