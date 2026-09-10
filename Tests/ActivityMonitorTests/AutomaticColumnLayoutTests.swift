import AppKit
import XCTest

@testable import ActivityMonitor

final class AutomaticColumnLayoutTests: XCTestCase {
  func testEveryDefaultViewAndSortFitsAcrossSupportedViewportWidths() {
    // Includes legacy scrollbar space and the former 900-point discontinuity.
    for width in stride(from: CGFloat(377), through: 1800, by: 13) {
      for metric in Metric.allCases {
        let defaults = ProcessColumns.defaults(metric)
        for sort in ["name"] + defaults.map(\.id) {
          let columns = ProcessColumnPolicy.visible(
            defaults, metric: metric, width: width, sort: sort)
          let layout = ProcessColumnLayout(
            viewport: width, metric: metric, columns: columns, saved: .init())
          XCTAssertEqual(layout.total, width, accuracy: 0.01, "\(metric) \(sort) at \(width)")
          XCTAssertGreaterThanOrEqual(layout.name, 180)
          if sort != "name" { XCTAssertTrue(columns.contains { $0.id == sort }) }
          for column in columns {
            XCTAssertGreaterThanOrEqual(
              layout.width(column.id) + 0.01, ProcessColumnLayout.minimum(column, metric: metric))
          }
        }
      }
    }
  }
  func testScreenshotSizedCPUAndMemoryKeepAllDefaultColumnsVisible() {
    for width: CGFloat in [885, 900, 985, 1000, 1040, 1080, 1200] {
      for metric in Metric.allCases {
        let columns = ProcessColumnPolicy.visible(
          ProcessColumns.defaults(metric), metric: metric, width: width,
          sort: metric == .network ? "received" : "primary")
        XCTAssertEqual(
          columns.map(\.id), ProcessColumns.defaults(metric).map(\.id), "\(metric) at \(width)")
        let layout = ProcessColumnLayout(
          viewport: width, metric: metric, columns: columns, saved: .init())
        XCTAssertEqual(layout.total, width, accuracy: 0.01)
        XCTAssertLessThanOrEqual(layout.offset("user") + layout.width("user"), width + 0.01)
      }
    }
  }
  func testMinimumHighlightedWidthsKeepCommonLargeValuesReadable() {
    for (metric, text) in [(Metric.cpu, "1000.0"), (.gpu, "1000.0"), (.memory, "1.023,9 MB")] {
      let primary = ProcessColumns.defaults(metric).first { $0.id == "primary" }!
      let width = ProcessColumnLayout.minimum(primary, metric: metric) - 34
      XCTAssertEqual(
        ProcessCellText.truncate(
          text, width: width,
          font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium)), text)
    }
  }
  func testDraggingFittedDividersPreservesAllNeighborWidths() {
    for metric in Metric.allCases {
      let columns = ProcessColumns.defaults(metric)
      for key in ["name"] + columns.map(\.id) {
        var saved = ProcessColumnWidths()
        let before = ProcessColumnLayout(
          viewport: 885, metric: metric, columns: columns, saved: saved)
        saved.resize(
          key, metric: metric, columns: columns, viewport: 885, to: before.width(key) + 37)
        let after = ProcessColumnLayout(
          viewport: 885, metric: metric, columns: columns, saved: saved)
        for neighbor in before.order {
          XCTAssertEqual(
            after.width(neighbor), before.width(neighbor) + (neighbor == key ? 37 : 0),
            accuracy: 0.01)
        }
        XCTAssertEqual(after.total, before.total + 37, accuracy: 0.01)
      }
    }
  }
  func testManualSizesAndOptionalColumnsCanIntentionallyExceedViewport() {
    var saved = ProcessColumnWidths()
    saved.set("name", metric: .cpu, width: 600)
    saved.set("primary", metric: .cpu, width: 220)
    let manual = ProcessColumnLayout(
      viewport: 885, metric: .cpu, columns: ProcessColumns.defaults(.cpu), saved: saved)
    XCTAssertEqual(manual.name, 600)
    XCTAssertEqual(manual.width("primary"), 220)
    XCTAssertGreaterThan(manual.total, 885)
    let optional = ProcessColumnLayout(
      viewport: 885, metric: .cpu, columns: ProcessColumns.available(.cpu), saved: .init())
    XCTAssertGreaterThan(optional.total, 885)
    saved.reset(.cpu)
    let restored = ProcessColumnLayout(
      viewport: 885, metric: .cpu, columns: ProcessColumns.defaults(.cpu), saved: saved)
    XCTAssertEqual(restored.total, 885, accuracy: 0.01)
  }
}
